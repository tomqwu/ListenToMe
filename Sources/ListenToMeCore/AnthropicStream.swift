import Foundation

/// Pure parsing of the Anthropic Messages API event stream (`POST /v1/messages` with
/// `"stream": true`), API version 2026-10-21 (issue #214).
///
/// Events: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`,
/// `message_delta` (carries `stop_reason`), `message_stop`, `ping` and `error`. Only `text_delta`
/// is answer text; `thinking_delta` and `signature_delta` belong to thinking blocks, which are never
/// shown or saved. Unknown event and block types (such as the `fallback` marker a server-side
/// fallback inserts) are skipped, so a new event type cannot break a stream.
struct AnthropicStreamState {
    let maximumBytes: Int
    private(set) var receivedBytes = 0
    /// Set by `message_stop`, the only event that completes a response.
    private(set) var finished = false
    private(set) var stopReason: String?
    private var producedContent = false
    private var producedThinking = false

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    mutating func receive(_ byteCount: Int) throws {
        receivedBytes += byteCount
        guard receivedBytes <= maximumBytes else { throw OpenAICompatibleError.tooLarge }
    }

    /// The answer text one line carries. Throws on an `error` event, a refusal, or a line that is not
    /// part of an event stream at all.
    mutating func consume(_ line: String, contentType: String?) throws -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(":") { return nil }
        if ["event:", "id:", "retry:"].contains(where: { trimmed.hasPrefix($0) }) { return nil }
        guard trimmed.hasPrefix("data:") else {
            if let object = OpenAICompatibleSSE.jsonObject(trimmed), let error = AnthropicError.streamError(in: object) {
                throw error
            }
            throw AnthropicError.notEventStream(contentType: contentType)
        }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let object = OpenAICompatibleSSE.jsonObject(payload) else {
            throw AnthropicError.notEventStream(contentType: contentType)
        }
        switch object["type"] as? String {
        case "content_block_start":
            let block = object["content_block"] as? [String: Any]
            switch block?["type"] as? String {
            case "thinking", "redacted_thinking": producedThinking = true
            case "text": return accept(block?["text"] as? String)
            default: break
            }
        case "content_block_delta":
            let delta = object["delta"] as? [String: Any]
            switch delta?["type"] as? String {
            case "text_delta": return accept(delta?["text"] as? String)
            case "thinking_delta", "signature_delta": producedThinking = true
            default: break
            }
        case "message_delta":
            let delta = object["delta"] as? [String: Any]
            if let reason = delta?["stop_reason"] as? String {
                stopReason = reason
                if reason == "refusal" {
                    let details = (delta?["stop_details"] as? [String: Any]) ?? (object["stop_details"] as? [String: Any])
                    throw AnthropicError.refused(category: details?["category"] as? String)
                }
            }
        case "message_stop": finished = true
        case "error": throw AnthropicError.streamError(in: object) ?? AnthropicError.stream(type: "error", message: nil)
        default: break   // message_start, content_block_stop, ping and future event types
        }
        return nil
    }

    private mutating func accept(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { producedContent = true }
        return text
    }

    /// Called once the byte stream ends. Only `message_stop` completes a response; a stream that was
    /// cut off is never accepted as a complete answer, and neither is one that hit the token cap.
    func complete() throws {
        guard finished else { throw OpenAICompatibleError.incomplete }
        if stopReason == "max_tokens" || stopReason == "model_context_window_exceeded" { throw AnthropicError.cutOff }
        guard producedContent else {
            throw producedThinking ? OpenAICompatibleError.thinkingOnly : OpenAICompatibleError.empty
        }
    }
}

public enum AnthropicError: LocalizedError, Equatable {
    /// 401/403: the key is missing, wrong or lacks access.
    case invalidKey(status: Int, detail: String?)
    /// 429 or 529: rate limited or overloaded, after the one retry `retry-after` allowed.
    case overloaded(status: Int, retryAfter: Int?, detail: String?)
    /// 400 `invalid_request_error`, with Anthropic's message (key masked).
    case invalidRequest(String)
    /// Any other non-2xx response.
    case http(status: Int, detail: String?)
    /// An `error` event inside the stream, such as `overloaded_error`.
    case stream(type: String, message: String?)
    /// `stop_reason: "refusal"`: Claude declined, after any server-side fallback.
    case refused(category: String?)
    /// `stop_reason: "max_tokens"`: the answer reached the length limit and was cut off.
    case cutOff
    /// A 2xx response that is not an event stream (proxy page, captive portal).
    case notEventStream(contentType: String?)

    public var errorDescription: String? {
        switch self {
        case let .invalidKey(status, detail):
            return "Anthropic rejected the API key (HTTP \(status)). Check your Claude API key in Settings."
                + (detail.map { " (\($0))" } ?? "")
        case let .overloaded(status, retryAfter, detail):
            let wait = retryAfter.map { " Anthropic asked to wait \($0) seconds." } ?? ""
            let kind = status == 529 ? "Anthropic is overloaded" : "Anthropic is rate limiting this API key"
            return "\(kind) (HTTP \(status)).\(wait) Try again shortly." + (detail.map { " (\($0))" } ?? "")
        case .invalidRequest(let message):
            return "Anthropic rejected the request: \(message)"
        case let .http(status, detail):
            return OpenAICompatibleError.httpDescription(status: status, detail: detail)
        case let .stream(type, message):
            let label = type == "overloaded_error" ? "Anthropic is overloaded" : "Anthropic reported an error"
            return "\(label) (\(type))" + (message.map { ": \($0)" } ?? ".") + " Try again shortly."
        case .refused(let category):
            let reason = category.map { " (\($0))" } ?? ""
            return "Claude declined to answer this request\(reason). Any partial text is not a complete answer. "
                + "Anthropic may have re-run it on another Claude model first. Rephrase, or choose another model."
        case .cutOff:
            return "The answer was cut off because it reached the length limit. The partial text is shown; "
                + "retry, or ask for a shorter answer."
        case .notEventStream(let contentType):
            let kind = contentType.map { " (it sent \($0))" } ?? ""
            return "Anthropic did not answer in its streaming format\(kind). Check that no login page or proxy "
                + "is in the way."
        }
    }

    /// `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`.
    static func streamError(in object: [String: Any]) -> AnthropicError? {
        guard let error = object["error"] as? [String: Any] else { return nil }
        let message = (error["message"] as? String).flatMap(OpenAICompatibleSSE.normalized)
        return .stream(type: (error["type"] as? String) ?? "error", message: message)
    }

    /// The typed error for a non-2xx response. `body` is bounded; the key is masked in every message.
    static func response(status: Int, body: Data, apiKey: String, retryAfter: Int?) -> AnthropicError {
        let detail = OpenAICompatibleError.detail(from: body, redacting: apiKey)
        let type = ((try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any])?["type"]
            as? String
        switch status {
        case 401, 403: return .invalidKey(status: status, detail: detail)
        case 429, 529: return .overloaded(status: status, retryAfter: retryAfter, detail: detail)
        case 400 where type == "invalid_request_error" || type == nil:
            return .invalidRequest(detail ?? "invalid request (HTTP 400).")
        default: return .http(status: status, detail: detail)
        }
    }
}
