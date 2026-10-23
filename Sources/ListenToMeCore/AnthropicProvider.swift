import Foundation

/// Streams answers from Claude through Anthropic's native Messages API (issue #214), over plain
/// `URLSession`: there is no Anthropic SDK for Swift, and an OpenAI-compatible shim would lose
/// refusals, effort and structured outputs.
///
/// The transport guarantees are the custom server's (#52): redirects are refused, cookies are never
/// stored or sent, responses are capped at 16 MiB, the stream must end with `message_stop`, and the
/// API key is masked in every error. On top of that:
/// - API version `2026-10-21`, which rejects `temperature`, `top_p` and `top_k`, so none are sent.
/// - Thinking cannot be turned off on Claude Opus 5.5 or Sonnet 5.5, so `thinking` is omitted and
///   depth is set with `output_config.effort`: `low` for Auto Quick's evaluator, `medium` otherwise
///   (set explicitly; Opus 5.5 defaults to `medium`, other models to `high`).
/// - The evaluator asks for structured output against the Quick Summary decision schema, so it
///   always gets valid JSON. Assistant prefill is never used; current models reject it.
/// - Opus 5.5 and Sonnet 5.5 chat requests opt into server-side refusal fallbacks
///   (`fallbacks: "default"`). On a stream, a fallback continues the partial answer on another
///   Claude model and nothing already received is invalidated, so the text simply carries on.
///   Structured-output (Quick evaluator) requests never send fallbacks, so the two options can never
///   combine into a rejected request. Any 400 to a request with fallbacks is retried once without
///   them; the model is remembered as not taking them only when that retry succeeds.
/// - HTTP 429 and 529 are retried once, only when `retry-after` (seconds or an HTTP date) asks for a
///   short wait.
public struct AnthropicProvider: LLMProvider {
    public struct Options: Sendable, Equatable {
        /// `output_config.effort` for everything except the Quick evaluator.
        public let effort: String
        /// `max_tokens` for everything except the Quick evaluator. Thinking counts against it.
        public let maximumTokens: Int
        public init(effort: String = "medium", maximumTokens: Int = 32_000) {
            self.effort = effort
            self.maximumTokens = maximumTokens
        }
    }

    public static let defaultBaseURL = URL(string: "https://api.anthropic.com/v1")!
    public static let apiVersion = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that take `fallbacks: "default"`.
    public static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]
    /// The evaluator's effort and token cap: thinking stays on, so the cap leaves room for it.
    public static let quickEffort = "low"
    public static let quickMaximumTokens = 8_192
    /// Longest `retry-after` the one automatic retry waits for.
    public static let maximumRetryDelay = 20

    public let id = "anthropic"
    public let model: String
    public let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let options: Options
    private let idleTimeout: TimeInterval
    private let maximumResponseBytes: Int
    private let sleep: @Sendable (Int) async throws -> Void

    public init(model: String, apiKey: String, baseURL: URL = AnthropicProvider.defaultBaseURL,
                urlSession: URLSession = .shared, options: Options = .init(), idleTimeout: TimeInterval = 120,
                maximumResponseBytes: Int = OpenAICompatibleProvider.defaultMaximumResponseBytes,
                sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = urlSession
        self.options = options
        self.idleTimeout = idleTimeout
        self.maximumResponseBytes = maximumResponseBytes
        self.sleep = sleep
    }

    /// Request headers. The key goes in `x-api-key` and nowhere else.
    public static func headers(apiKey: String, fallbacks: Bool) -> [String: String] {
        var headers = ["x-api-key": apiKey, "anthropic-version": apiVersion, "content-type": "application/json"]
        if fallbacks { headers["anthropic-beta"] = fallbackBeta }
        return headers
    }

    /// The `/v1/messages` body: no sampling parameters, no `thinking`, no prefill.
    public static func requestBody(model: String, request: LLMRequest, options: Options = .init(),
                                   fallbacks: Bool) -> Data {
        let quick = request.purpose == .quickEvaluation
        var outputConfig: [String: Any] = ["effort": quick ? quickEffort : options.effort]
        if quick { outputConfig["format"] = ["type": "json_schema", "schema": QuickSummaryDecision.jsonSchema] }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": quick ? quickMaximumTokens : options.maximumTokens,
            "messages": messages(request.messages),
            "stream": true,
            "output_config": outputConfig
        ]
        if !request.system.isEmpty { body["system"] = request.system }
        if fallbacks { body["fallbacks"] = "default" }
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// The Messages API takes alternating `user`/`assistant` turns that start with `user`; anything
    /// else the app builds is folded into that shape rather than rejected.
    static func messages(_ input: [ChatMessage]) -> [[String: String]] {
        var turns: [[String: String]] = []
        for message in input where !message.content.isEmpty {
            let role = message.role == "assistant" ? "assistant" : "user"
            if turns.isEmpty && role == "assistant" { continue }
            if let last = turns.last, last["role"] == role {
                turns[turns.count - 1]["content"] = (last["content"] ?? "") + "\n\n" + message.content
            } else {
                turns.append(["role": role, "content": message.content])
            }
        }
        if turns.last?["role"] == "assistant" { turns.removeLast() }   // never a prefill
        return turns.isEmpty ? [["role": "user", "content": "(empty)"]] : turns
    }

    public func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request) { continuation.yield(.content($0)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error, host: baseURL, apiKey: apiKey))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let events = streamEvents(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case .content(let delta) = event { continuation.yield(delta) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func urlRequest(_ request: LLMRequest, fallbacks: Bool) -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = idleTimeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in Self.headers(apiKey: apiKey, fallbacks: fallbacks) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        urlRequest.httpBody = Self.requestBody(model: model, request: request, options: options, fallbacks: fallbacks)
        return urlRequest
    }

    /// Opens the stream, retrying at most once without fallbacks (if the model rejects them) and at
    /// most once after a 429/529 whose `retry-after` is short.
    private func open(_ request: LLMRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var fallbacks = Self.sendsFallbacks(model: model, request: request)
        var droppedFallbacks = false
        var retriedOverload = false
        while true {
            do {
                let opened = try await AnthropicTransport.open(urlRequest(request, fallbacks: fallbacks),
                                                               session: session, apiKey: apiKey)
                // Only a request that works without fallbacks proves they were what the API refused.
                if droppedFallbacks { AnthropicFallbackSupport.shared.reject(model) }
                return opened
            } catch AnthropicError.invalidRequest where fallbacks {
                fallbacks = false
                droppedFallbacks = true
            } catch let AnthropicError.overloaded(status, retryAfter, detail) where !retriedOverload {
                guard let delay = retryAfter, delay <= Self.maximumRetryDelay else {
                    throw AnthropicError.overloaded(status: status, retryAfter: retryAfter, detail: detail)
                }
                retriedOverload = true
                try await sleep(delay)
            }
        }
    }

    /// Fallbacks go only on chat requests to the models that take them, never with structured output.
    static func sendsFallbacks(model: String, request: LLMRequest) -> Bool {
        request.purpose != .quickEvaluation && fallbackModels.contains(model)
            && !AnthropicFallbackSupport.shared.isRejected(model)
    }

    private func run(_ request: LLMRequest, yield: (String) -> Void) async throws {
        let (bytes, http) = try await open(request)
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        var state = AnthropicStreamState(maximumBytes: maximumResponseBytes)
        if contentType?.lowercased().contains("json") == true {
            // A JSON body on a streaming request can only be an error, or something in the way.
            let body = try await OpenAICompatibleTransport.collect(bytes, limit: maximumResponseBytes, throwing: true)
            if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let error = AnthropicError.streamError(in: object) { throw error }
            throw AnthropicError.notEventStream(contentType: contentType)
        }
        var line: [UInt8] = []
        line.reserveCapacity(1_024)
        var afterCarriageReturn = false
        func handle() throws {
            try Task.checkCancellation()
            if let text = try state.consume(String(decoding: line, as: UTF8.self), contentType: contentType) {
                yield(text)
            }
            line.removeAll(keepingCapacity: true)
        }
        for try await byte in bytes {
            try state.receive(1)
            let wasCarriageReturn = afterCarriageReturn
            afterCarriageReturn = byte == UInt8(ascii: "\r")
            if byte == UInt8(ascii: "\n") && wasCarriageReturn { continue }
            if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                try handle()
                if state.finished { break }
            } else {
                line.append(byte)
                guard line.count <= OpenAICompatibleProvider.maximumLineBytes else { throw OpenAICompatibleError.tooLarge }
            }
        }
        if !state.finished, !line.isEmpty { try handle() }
        try Task.checkCancellation()
        try state.complete()
    }

    /// Connection failures name the host; cancellation stays cancellation; server text is masked.
    static func mapped(_ error: Error, host: URL, apiKey: String) -> Error {
        switch error {
        case AnthropicError.stream(let type, let message?):
            return AnthropicError.stream(type: type, message: OpenAICompatibleError.redact(message, apiKey))
        default:
            return OpenAICompatibleTransport.mapped(error, host: host, apiKey: apiKey)
        }
    }
}

/// HTTP plumbing for Anthropic: the custom server's redirect refusal and bounded error bodies, with
/// Anthropic's own status meanings.
enum AnthropicTransport {
    static func open(_ request: URLRequest, session: URLSession,
                     apiKey: String) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.notEventStream(contentType: nil) }
        if (300...399).contains(http.statusCode) {
            let location = http.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: request.url) }
            throw OpenAICompatibleError.redirected(status: http.statusCode,
                                                   location: location.map(OpenAICompatibleEndpoint.hostLabel))
        }
        if let final = http.url, let sent = request.url,
           OpenAICompatibleEndpoint.origin(of: final) != OpenAICompatibleEndpoint.origin(of: sent) {
            throw OpenAICompatibleError.redirected(status: http.statusCode, location: OpenAICompatibleEndpoint.hostLabel(final))
        }
        guard (200...299).contains(http.statusCode) else {
            let body = (try? await OpenAICompatibleTransport.collect(
                bytes, limit: OpenAICompatibleError.maximumErrorBodyBytes, throwing: false)) ?? Data()
            throw AnthropicError.response(status: http.statusCode, body: body, apiKey: apiKey,
                                      retryAfter: retryAfter(http.value(forHTTPHeaderField: "retry-after")))
        }
        return (bytes, http)
    }

    /// Whole seconds from a `retry-after` header: delta-seconds (fractions round up) or an HTTP
    /// date, measured from `now`. A date in the past means retry now.
    static func retryAfter(_ value: String?, now: Date = Date()) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value) { return seconds >= 0 ? Int(seconds.rounded(.up)) : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, Int(date.timeIntervalSince(now).rounded(.up)))
    }
}

/// Models that rejected `fallbacks` this run, so later requests do not pay for a failed attempt.
final class AnthropicFallbackSupport: @unchecked Sendable {
    static let shared = AnthropicFallbackSupport()
    private let lock = NSLock()
    private var rejected: Set<String> = []

    func isRejected(_ model: String) -> Bool { lock.withLock { rejected.contains(model) } }
    func reject(_ model: String) { _ = lock.withLock { rejected.insert(model) } }
    func reset() { lock.withLock { rejected.removeAll() } }
}

public extension QuickSummaryDecision {
    /// The decision envelope `QuickSummaryDecision.parse` accepts, as a JSON schema for structured
    /// outputs. Length and count limits are not expressible there; `parse` still enforces them.
    static var jsonSchema: [String: Any] {
        let review: [String: Any] = [
            "type": "object",
            "properties": [
                "mode": ["type": "string", "enum": ["summary", "deep"]],
                "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
                "reason": ["type": "string"]
            ],
            "required": ["mode", "confidence", "reason"],
            "additionalProperties": false
        ]
        return [
            "type": "object",
            "properties": [
                "action": ["type": "string", "enum": ["keep", "publish"]],
                "context": ["type": "string"],
                "bullets": ["type": "array", "items": ["type": "string"]],
                "reviews": ["type": "array", "items": review]
            ],
            "required": ["action", "context", "bullets", "reviews"],
            "additionalProperties": false
        ]
    }
}
