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
                urlSession: URLSession = .shared) {
        self.init(model: model, baseURL: baseURL,
                  lineSource: Self.makeLiveLineSource(model: model, baseURL: baseURL, session: urlSession))
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
                    for try await line in lineSource(request) {
                        if Task.isCancelled { break }
                        if let delta = OllamaParser.delta(fromLine: line), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        if OllamaParser.isDone(line: line) { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeLiveLineSource(
        model: String, baseURL: URL, session: URLSession
    ) -> @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error> {
        return { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                        urlRequest.httpMethod = "POST"
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        urlRequest.httpBody = requestBody(model: model, request: request)
                        let (bytes, response) = try await session.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            throw NSError(
                                domain: "Ollama", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Ollama returned HTTP \(http.statusCode). Is the server running and the model pulled?"])
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
