import Foundation

/// Pure parsing of Ollama's NDJSON streaming responses (`/api/chat`).
public enum OllamaParser {
    public static func delta(fromLine line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }

    public static func isDone(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (obj["done"] as? Bool) == true
    }
}

/// Streams chat completions from a local (or remote) Ollama server.
public struct OllamaProvider: LLMProvider {
    public let id = "ollama"
    private let model: String
    /// The endpoint this provider talks to; exposed so callers can show the destination host.
    public let baseURL: URL
    private let lineSource: @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>

    /// Designated initializer. `lineSource` yields raw NDJSON lines; injectable for testing.
    public init(model: String, baseURL: URL,
                lineSource: @escaping @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>) {
        self.model = model
        self.baseURL = baseURL
        self.lineSource = lineSource
    }

    /// Live initializer that talks to a real Ollama server over HTTP.
    public init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!,
                apiKey: String? = nil, urlSession: URLSession = .shared, localOnly: Bool = false,
                options: OllamaGenerationOptions = .init()) {
        self.init(model: model, baseURL: baseURL,
                  lineSource: Self.makeLiveLineSource(
                    model: model, baseURL: baseURL, apiKey: apiKey, session: urlSession, localOnly: localOnly, options: options))
    }

    public static func requestBody(model: String, request: LLMRequest, options: OllamaGenerationOptions = .init()) -> Data {
        let options = request.purpose == .quickEvaluation
            ? OllamaGenerationOptions(thinking: false, temperature: 0, maximumTokens: 3072) : options
        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        messages += request.messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        if let thinking = options.thinking { body["think"] = thinking }
        var generation: [String: Any] = [:]
        if let temperature = options.temperature { generation["temperature"] = temperature }
        if let maximumTokens = options.maximumTokens { generation["num_predict"] = maximumTokens }
        if !generation.isEmpty { body["options"] = generation }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var completed = false
                    var producedContent = false
                    for try await line in lineSource(request) {
                        try Task.checkCancellation()
                        if let data = line.data(using: .utf8),
                           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = object["error"] as? String { throw OllamaStreamError.server(error) }
                        if let delta = OllamaParser.delta(fromLine: line), !delta.isEmpty {
                            producedContent = producedContent || !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            continuation.yield(delta)
                        }
                        if OllamaParser.isDone(line: line) { completed = true; break }
                    }
                    try Task.checkCancellation()
                    guard completed else { throw OllamaStreamError.incomplete }
                    guard producedContent else { throw OllamaStreamError.empty }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeLiveLineSource(
        model: String, baseURL: URL, apiKey: String? = nil, session: URLSession, localOnly: Bool,
        options: OllamaGenerationOptions
    ) -> @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error> {
        return { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    // Never follow redirects with meeting text in local-only mode.
                    let transport = localOnly
                        ? URLSession(configuration: session.configuration, delegate: RejectRedirects(), delegateQueue: nil)
                        : session
                    defer { if localOnly { transport.invalidateAndCancel() } }
                    do {
                        if localOnly {
                            guard ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "") else {
                                throw OllamaStreamError.server("Local-only mode requires a local Ollama server.")
                            }
                            var check = URLRequest(url: baseURL.appendingPathComponent("api/show"))
                            check.httpMethod = "POST"; check.timeoutInterval = 10
                            check.setValue("application/json", forHTTPHeaderField: "Content-Type")
                            check.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
                            let (metadata, response) = try await transport.data(for: check)
                            guard (response as? HTTPURLResponse)?.statusCode == 200,
                                  ModelPrivacy.isVerifiedLocal(metadata) else {
                                throw OllamaStreamError.server("This model could not be verified as local. " +
                                    "Choose a downloaded local model or explicitly enable Cloud in Settings.")
                            }
                        }
                        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                        urlRequest.httpMethod = "POST"
                        urlRequest.timeoutInterval = 90
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        if let apiKey, !apiKey.isEmpty {
                            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        }
                        urlRequest.httpBody = requestBody(model: model, request: request, options: options)
                        let (bytes, response) = try await transport.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            // Read (a bounded prefix of) the body so the server's own explanation —
                            // bad key, exhausted quota, unsupported option — reaches the user.
                            let body = await Self.boundedBody(bytes)
                            throw OllamaStreamError.fromHTTP(status: http.statusCode, body: body)
                        }
                        for try await line in bytes.lines {
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch let error as URLError {
                        // Connection-level failure: this is the only case where "is the server
                        // running / the model pulled" is the right advice.
                        continuation.finish(throwing: OllamaStreamError.unreachable(error.localizedDescription))
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    /// Collects at most `OllamaStreamError.maximumErrorBodyBytes` of an error response body.
    private static func boundedBody(_ bytes: URLSession.AsyncBytes) async -> Data {
        var data = Data()
        data.reserveCapacity(OllamaStreamError.maximumErrorBodyBytes)
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= OllamaStreamError.maximumErrorBodyBytes { break }
            }
        } catch {
            // A truncated body is still better than no explanation at all.
        }
        return data
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum OllamaStreamError: LocalizedError {
    case server(String)
    /// The request never reached a server (connection refused, DNS, timeout, TLS).
    case unreachable(String)
    case incomplete
    case empty
    public var errorDescription: String? {
        switch self {
        case .server(let message): return "Model error: " + message
        case .unreachable(let message):
            return message + " Is the server running and the model pulled?"
        case .incomplete: return "The response ended before completion. Partial text is kept; retry the request."
        case .empty: return "The model completed without an answer. Retry or choose another model."
        }
    }

    /// Bytes of an error body we are willing to read and show. Bounded so an HTML error page or a
    /// runaway server cannot flood a pane (or memory).
    public static let maximumErrorBodyBytes = 8 * 1024

    /// Builds the error for a non-2xx response, using the server's own `{"error": ...}` text when
    /// present. Status-specific hints keep cloud auth/quota failures from reading as "model not
    /// pulled" (issue #118).
    public static func fromHTTP(status: Int, body: Data) -> OllamaStreamError {
        var text = "HTTP \(status)"
        let hint = statusHint(status)
        let detail = serverDetail(body)
        switch (hint, detail) {
        case let (hint?, detail?): text += ": \(hint) (\(detail))"
        case let (hint?, nil):     text += ": \(hint)"
        case let (nil, detail?):   text += ": \(detail)"
        case (nil, nil):           text += ": the server returned no error details."
        }
        return .server(text)
    }

    private static func statusHint(_ status: Int) -> String? {
        switch status {
        case 401, 403:
            return "API key rejected — check the Ollama API key in Settings."
        case 429:
            return "Rate limited or out of quota — wait and retry, or check your Ollama plan."
        case 404:
            return "Model or endpoint not found — check the model name and that it is pulled."
        case 500...599:
            return "The Ollama server failed to handle the request."
        default:
            return nil
        }
    }

    /// The server's own explanation: a top-level `error` string, `error.message`, or (failing JSON)
    /// the raw body. Always bounded to `maximumErrorBodyBytes`.
    private static func serverDetail(_ body: Data) -> String? {
        let bounded = body.prefix(maximumErrorBodyBytes)
        if let object = try? JSONSerialization.jsonObject(with: Data(bounded)) as? [String: Any] {
            if let message = object["error"] as? String { return normalize(message) }
            if let nested = object["error"] as? [String: Any], let message = nested["message"] as? String {
                return normalize(message)
            }
        }
        // The 8 KiB cut can land mid-codepoint; drop the replacement character it decodes to
        // rather than showing the user a stray "".
        var text = String(decoding: bounded, as: UTF8.self)
        while text.last == "\u{FFFD}" { text.removeLast() }
        return normalize(text)
    }

    private static func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
