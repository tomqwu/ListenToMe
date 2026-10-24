import Foundation

/// Streams chat completions from any OpenAI-compatible `/v1/chat/completions` server: LM Studio,
/// vLLM, llama.cpp, OpenRouter, or Ollama's own `/v1` API (issue #52).
///
/// The transport contract matches `OllamaProvider`: non-2xx bodies are bounded and surfaced, the
/// stream must end explicitly (`[DONE]` or a `finish_reason`), it must contain an answer, server
/// error objects fail the request, and the response is size-limited. On top of that, redirects are
/// never followed (the request carries the transcript and possibly a bearer key), cookies are not
/// stored or sent, and an API key is never echoed back in an error message.
public struct OpenAICompatibleProvider: LLMProvider {
    public struct Options: Sendable, Equatable {
        public let temperature: Double?
        public let maximumTokens: Int?
        public init(temperature: Double? = nil, maximumTokens: Int? = nil) {
            self.temperature = temperature
            self.maximumTokens = maximumTokens
        }
    }

    public let id = "openai-compatible"
    public let model: String
    /// The API base (ending in the version path, such as `/v1`); exposed so callers can name it.
    public let baseURL: URL
    private let apiKey: String?
    private let session: URLSession
    private let options: Options
    private let idleTimeout: TimeInterval
    private let maximumResponseBytes: Int
    /// The vendor's request shape (issue #214); `.standard` for a server the user typed.
    public let dialect: OpenAICompatibleDialect

    /// Default cap on everything one response streams, framing included. Event-stream framing costs
    /// roughly 150 bytes per token, so this comfortably fits the apps' 100,000-character answers.
    public static let defaultMaximumResponseBytes = 16 * 1024 * 1024
    /// Longest single line accepted; a server that never sends a newline cannot grow memory.
    static let maximumLineBytes = 1024 * 1024

    public init(model: String, baseURL: URL, apiKey: String? = nil, urlSession: URLSession = .shared,
                options: Options = .init(), idleTimeout: TimeInterval = 90,
                maximumResponseBytes: Int = OpenAICompatibleProvider.defaultMaximumResponseBytes,
                dialect: OpenAICompatibleDialect = .standard) {
        self.dialect = dialect
        self.model = model
        self.baseURL = baseURL
        self.apiKey = (apiKey?.isEmpty ?? true) ? nil : apiKey
        self.session = urlSession
        self.options = options
        self.idleTimeout = idleTimeout
        self.maximumResponseBytes = maximumResponseBytes
    }

    /// The `/chat/completions` body. Auto Quick's evaluator gets the same controls as on Ollama:
    /// temperature zero and 3,072 output tokens (`LLMRequest.Purpose.quickEvaluation`), plus
    /// best-effort requests to skip reasoning, the counterpart of Ollama's `think: false`:
    /// `reasoning_effort: "none"` (Ollama's `/v1`, OpenAI, vLLM) and
    /// `chat_template_kwargs.enable_thinking: false` (Qwen-style templates on vLLM and llama.cpp).
    /// Servers that do not know them ignore them; a strict server that rejects them with 400/422
    /// gets the request again without them (`reasoningHints: false`).
    /// A preset's `dialect` renames the token cap, drops the temperature or picks the vendor's own hint.
    public static func requestBody(model: String, request: LLMRequest, options: Options = .init(),
                                   reasoningHints: Bool = true, dialect: OpenAICompatibleDialect = .standard) -> Data {
        let quick = request.purpose == .quickEvaluation
        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        messages += request.messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        if dialect.sendsTemperature, let temperature = quick ? 0 : options.temperature { body["temperature"] = temperature }
        if let maximumTokens = quick ? 3_072 : options.maximumTokens { body[dialect.maximumTokensField] = maximumTokens }
        if quick && reasoningHints { dialect.addQuickReasoningHints(to: &body) }
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    public func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    let mapped = OpenAICompatibleTransport.mapped(error, host: baseURL, apiKey: apiKey)
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        LLMOutputLimit.textStream(streamEvents(request))
    }

    private func open(_ request: LLMRequest,
                      reasoningHints: Bool) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var urlRequest = OpenAICompatibleTransport.request(
            OpenAICompatibleEndpoint.chatURL(baseURL), apiKey: apiKey, timeout: idleTimeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in dialect.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = Self.requestBody(model: model, request: request, options: options,
                                               reasoningHints: reasoningHints, dialect: dialect)
        return try await OpenAICompatibleTransport.open(urlRequest, session: session, apiKey: apiKey)
    }

    private func run(_ request: LLMRequest, yield: (LLMStreamEvent) -> Void) async throws {
        let bytes: URLSession.AsyncBytes, http: HTTPURLResponse
        do {
            (bytes, http) = try await open(request, reasoningHints: true)
        } catch let OpenAICompatibleError.http(status, _)
                    where request.purpose == .quickEvaluation && (status == 400 || status == 422) {
            // A strict server refused the reasoning hints; nothing was generated, so ask once without.
            (bytes, http) = try await open(request, reasoningHints: false)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        var state = OpenAICompatibleStreamState(maximumBytes: maximumResponseBytes)
        if contentType?.lowercased().contains("json") == true {
            // A server that ignored "stream": true answers with one JSON completion.
            let body = try await OpenAICompatibleTransport.collect(bytes, limit: maximumResponseBytes, throwing: true)
            try Task.checkCancellation()
            for event in try Self.wholeCompletion(body, state: &state) { yield(event) }
            try state.complete()
            if state.reachedOutputLimit { yield(.outputLimitReached) }
            return
        }
        var line: [UInt8] = []
        line.reserveCapacity(1_024)
        var afterCarriageReturn = false
        func handle() throws {
            try Task.checkCancellation()
            for event in try state.consume(String(decoding: line, as: UTF8.self), contentType: contentType) {
                yield(event)
            }
            line.removeAll(keepingCapacity: true)
        }
        // Lines end in LF, CRLF or a bare CR, as the event-stream format allows.
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
                guard line.count <= Self.maximumLineBytes else { throw OpenAICompatibleError.tooLarge }
            }
        }
        if !state.finished, !line.isEmpty { try handle() }
        try Task.checkCancellation()
        try state.complete()
        // `finish_reason: "length"`: the answer is partial, and says so (issue #215).
        if state.reachedOutputLimit { yield(.outputLimitReached) }
    }

    static func wholeCompletion(_ body: Data, state: inout OpenAICompatibleStreamState) throws -> [LLMStreamEvent] {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw OpenAICompatibleError.notEventStream(contentType: "application/json")
        }
        if let message = OpenAICompatibleSSE.errorMessage(in: object) { throw OpenAICompatibleError.server(message) }
        guard let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw OpenAICompatibleError.notEventStream(contentType: "application/json")
        }
        return state.acceptWhole(
            content: message["content"] as? String, finishReason: choice["finish_reason"] as? String,
            thinking: (message["reasoning_content"] as? String) ?? (message["reasoning"] as? String))
    }
}

/// HTTP plumbing shared by the provider and the model catalog.
enum OpenAICompatibleTransport {
    static func request(_ url: URL, apiKey: String?, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Sends `request` without following redirects and returns the body stream of a 2xx response.
    /// Anything else becomes a typed error carrying the server's bounded, key-redacted explanation.
    static func open(_ request: URLRequest, session: URLSession,
                     apiKey: String?) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleError.notEventStream(contentType: nil)
        }
        if (300...399).contains(http.statusCode) {
            let location = http.value(forHTTPHeaderField: "Location")
                .flatMap { URL(string: $0, relativeTo: request.url) }
            throw OpenAICompatibleError.redirected(
                status: http.statusCode, location: location.map(OpenAICompatibleEndpoint.hostLabel))
        }
        // Defense in depth: if anything below us followed a redirect anyway, refuse its answer.
        if let final = http.url, let sent = request.url,
           OpenAICompatibleEndpoint.origin(of: final) != OpenAICompatibleEndpoint.origin(of: sent) {
            throw OpenAICompatibleError.redirected(
                status: http.statusCode, location: OpenAICompatibleEndpoint.hostLabel(final))
        }
        guard (200...299).contains(http.statusCode) else {
            let limit = OpenAICompatibleError.maximumErrorBodyBytes
            let body = (try? await collect(bytes, limit: limit, throwing: false)) ?? Data()
            throw OpenAICompatibleError.http(status: http.statusCode,
                                             detail: OpenAICompatibleError.detail(from: body, redacting: apiKey))
        }
        return (bytes, http)
    }

    /// Reads at most `limit` bytes. Past the limit it throws `tooLarge`, or truncates when
    /// `throwing` is false (an error body is still worth showing in part).
    static func collect(_ bytes: URLSession.AsyncBytes, limit: Int, throwing: Bool) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else {
                if throwing { throw OpenAICompatibleError.tooLarge }
                break
            }
            data.append(byte)
        }
        return data
    }

    /// Connection failures name the host; cancellation stays cancellation; server text is redacted.
    static func mapped(_ error: Error, host: URL, apiKey: String?) -> Error {
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return CancellationError() }
            let reason = urlError.code == .timedOut
                ? "The request timed out." : urlError.localizedDescription
            return OpenAICompatibleError.unreachable(host: OpenAICompatibleEndpoint.hostLabel(host), reason: reason)
        }
        if case OpenAICompatibleError.server(let message) = error {
            return OpenAICompatibleError.server(OpenAICompatibleError.redact(message, apiKey))
        }
        return error
    }
}

/// Declines every redirect, so the 3xx itself comes back and is reported instead of followed.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
