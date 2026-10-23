import Foundation

/// Pure parsing of one line of an OpenAI-compatible `text/event-stream` (`/v1/chat/completions`
/// with `"stream": true`).
public enum OpenAICompatibleSSE {
    public enum Line: Equatable, Sendable {
        /// A blank line, a `:` comment (OpenRouter's keep-alives) or an `event:`/`id:`/`retry:` field.
        case ignore
        /// `data: [DONE]`, the stream's explicit end.
        case done
        /// A completion chunk. `content` is answer text, `thinking` is reasoning a model reports
        /// separately (`reasoning_content` or `reasoning`), `finishReason` is set on the last chunk.
        case chunk(content: String?, thinking: String?, finishReason: String?)
        /// The server reported an error inside the stream.
        case error(String)
        /// Not an event-stream line at all (an HTML login page, a proxy's banner, plain text).
        case unexpected
    }

    public static func parse(_ line: String) -> Line {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(":") { return .ignore }
        if ["event:", "id:", "retry:"].contains(where: { trimmed.hasPrefix($0) }) { return .ignore }
        guard trimmed.hasPrefix("data:") else {
            // Some servers answer a bad request with a bare JSON error even when asked to stream.
            if let object = jsonObject(trimmed), let message = errorMessage(in: object) { return .error(message) }
            return .unexpected
        }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let object = jsonObject(payload) else { return .unexpected }
        if let message = errorMessage(in: object) { return .error(message) }
        let choice = (object["choices"] as? [[String: Any]])?.first
        let delta = choice?["delta"] as? [String: Any]
        let finishReason = choice?["finish_reason"] as? String
        if finishReason == "error" { return .error("The server ended the response with an error.") }
        return .chunk(content: delta?["content"] as? String,
                      thinking: (delta?["reasoning_content"] as? String) ?? (delta?["reasoning"] as? String),
                      finishReason: finishReason)
    }

    /// The text of a top-level `error` (a string, or an object with `message`), if any.
    public static func errorMessage(in object: [String: Any]) -> String? {
        if let message = object["error"] as? String { return normalized(message) ?? "The server reported an error." }
        if let nested = object["error"] as? [String: Any] {
            return (nested["message"] as? String).flatMap(normalized) ?? "The server reported an error."
        }
        return nil
    }

    static func jsonObject(_ text: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The termination contract for one streamed response, matching `OllamaProvider`'s: a response only
/// counts when the server says it finished (`[DONE]` or a `finish_reason`), it must contain an
/// answer, and it may not exceed the byte budget.
struct OpenAICompatibleStreamState {
    let maximumBytes: Int
    private(set) var receivedBytes = 0
    private(set) var finished = false
    private var sawFinishReason = false
    private var producedContent = false
    private var producedThinking = false

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    /// Counts `byteCount` received bytes against the budget.
    mutating func receive(_ byteCount: Int) throws {
        receivedBytes += byteCount
        guard receivedBytes <= maximumBytes else { throw OpenAICompatibleError.tooLarge }
    }

    /// The events one line produces. Throws on a server error or a line that is not an event stream.
    mutating func consume(_ line: String, contentType: String?) throws -> [LLMStreamEvent] {
        switch OpenAICompatibleSSE.parse(line) {
        case .ignore: return []
        case .done:
            finished = true
            return []
        case .error(let message): throw OpenAICompatibleError.server(message)
        case .unexpected: throw OpenAICompatibleError.notEventStream(contentType: contentType)
        case let .chunk(content, thinking, finishReason):
            var events: [LLMStreamEvent] = []
            if let thinking, !thinking.isEmpty {
                producedThinking = producedThinking || !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                events.append(.thinking(thinking))
            }
            if let content, !content.isEmpty {
                producedContent = producedContent || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                events.append(.content(content))
            }
            if finishReason != nil { sawFinishReason = true }
            return events
        }
    }

    /// Records a complete non-streamed answer (a server that ignored `"stream": true`).
    mutating func acceptWhole(content: String?, thinking: String?) -> [LLMStreamEvent] {
        finished = true
        var events: [LLMStreamEvent] = []
        if let thinking, !thinking.isEmpty {
            producedThinking = !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            events.append(.thinking(thinking))
        }
        if let content, !content.isEmpty {
            producedContent = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            events.append(.content(content))
        }
        return events
    }

    /// Called once the byte stream ends. A stream that stopped without `[DONE]` or a finish reason
    /// was cut off: its partial text is never accepted as a complete answer.
    func complete() throws {
        guard finished || sawFinishReason else { throw OpenAICompatibleError.incomplete }
        guard producedContent else {
            throw producedThinking ? OpenAICompatibleError.thinkingOnly : OpenAICompatibleError.empty
        }
    }
}

public enum OpenAICompatibleError: LocalizedError, Equatable {
    /// The server's own error text, from the stream or a JSON error body.
    case server(String)
    /// A non-2xx, non-redirect response, with the server's explanation when it gave one.
    case http(status: Int, detail: String?)
    /// The server answered with a redirect. Redirects are never followed: a 3xx could carry the
    /// transcript and API key to a host the user never entered.
    case redirected(status: Int, location: String?)
    /// The request never reached the server (refused, DNS, TLS, timeout).
    case unreachable(host: String, reason: String)
    /// A 2xx response that is not an OpenAI event stream (captive portal, proxy page, wrong URL).
    case notEventStream(contentType: String?)
    case incomplete
    case empty
    case thinkingOnly
    case tooLarge
    case invalidModelList

    public var errorDescription: String? {
        switch self {
        case .server(let message): return "Model error: " + message
        case let .http(status, detail): return Self.httpDescription(status: status, detail: detail)
        case let .redirected(status, location):
            let target = location.map { " to \($0)" } ?? ""
            return "The server answered with a redirect (HTTP \(status))\(target). ListenToMe does not follow "
                + "redirects with your transcript or API key; enter the final server URL in Settings."
        case let .unreachable(host, reason):
            return "Could not reach \(host): \(reason) Check that the server is running and the URL is right."
        case .notEventStream(let contentType):
            let kind = contentType.map { " (it sent \($0))" } ?? ""
            return "The server did not answer in the OpenAI-compatible streaming format\(kind). "
                + "Check that the URL ends in the API base, such as /v1, and that no login page or proxy is in the way."
        case .incomplete: return "The response ended before completion. Partial text is kept; retry the request."
        case .empty: return "The model completed without an answer. Retry or choose another model."
        case .thinkingOnly:
            return "The model spent the whole response on reasoning and never answered. "
                + "Retry, or choose a model that does not think before answering."
        case .tooLarge: return "The server's response was larger than ListenToMe accepts, so it was stopped."
        case .invalidModelList:
            return "The server's /models response was not an OpenAI-compatible model list."
        }
    }

    /// Bytes of an error body read and shown, as for Ollama.
    public static let maximumErrorBodyBytes = OllamaStreamError.maximumErrorBodyBytes

    static func httpDescription(status: Int, detail: String?) -> String {
        var text = "HTTP \(status)"
        switch (statusHint(status), detail) {
        case let (hint?, detail?): text += ": \(hint) (\(detail))"
        case let (hint?, nil): text += ": \(hint)"
        case let (nil, detail?): text += ": \(detail)"
        case (nil, nil): text += ": the server returned no error details."
        }
        return text
    }

    private static func statusHint(_ status: Int) -> String? {
        switch status {
        case 401, 403: return "API key rejected — check the API key for this server in Settings."
        case 404:
            return "Model or endpoint not found — check the model name and that the URL ends in the API base, "
                + "such as /v1."
        case 429: return "Rate limited or out of credits — wait and retry, or check your plan with this provider."
        case 500...599: return "The server failed to handle the request."
        default: return nil
        }
    }

    /// The server's explanation from an error body: `error`/`error.message` JSON, else the raw text.
    /// Bounded, and with `apiKey` masked, since some servers echo the credential they rejected.
    static func detail(from body: Data, redacting apiKey: String?) -> String? {
        let bounded = Data(body.prefix(maximumErrorBodyBytes))
        var text: String
        if let object = try? JSONSerialization.jsonObject(with: bounded) as? [String: Any],
           let message = OpenAICompatibleSSE.errorMessage(in: object) {
            text = message
        } else {
            text = String(decoding: bounded, as: UTF8.self)
            while text.last == "\u{FFFD}" { text.removeLast() }
        }
        return OpenAICompatibleSSE.normalized(redact(text, apiKey))
    }

    static func redact(_ text: String, _ apiKey: String?) -> String {
        guard let apiKey, apiKey.count >= 4 else { return text }
        return text.replacingOccurrences(of: apiKey, with: "[API key]")
    }
}
