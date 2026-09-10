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
    private let baseURL: URL
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
                apiKey: String? = nil, urlSession: URLSession = .shared, localOnly: Bool = false) {
        self.init(model: model, baseURL: baseURL,
                  lineSource: Self.makeLiveLineSource(
                    model: model, baseURL: baseURL, apiKey: apiKey, session: urlSession, localOnly: localOnly))
    }

    public static func requestBody(model: String, request: LLMRequest) -> Data {
        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        messages += request.messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
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
        model: String, baseURL: URL, apiKey: String? = nil, session: URLSession, localOnly: Bool
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
                        urlRequest.httpBody = requestBody(model: model, request: request)
                        let (bytes, response) = try await transport.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            throw NSError(
                                domain: "Ollama", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Ollama returned HTTP \(http.statusCode)." +
                                    " Is the server running and the model pulled?"])
                        }
                        for try await line in bytes.lines {
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
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
    case incomplete
    case empty
    public var errorDescription: String? {
        switch self {
        case .server(let message): return "Model error: " + message
        case .incomplete: return "The response ended before completion. Partial text is kept; retry the request."
        case .empty: return "The model completed without an answer. Retry or choose another model."
        }
    }
}
