import Foundation

/// Pure parsing of DeepSeek's SSE streaming responses (`/chat/completions`).
public enum DeepSeekParser {
    public static func delta(fromLine line: String) -> String? {
        let stripped = stripDataPrefix(line)
        guard !stripped.isEmpty else { return nil }
        guard stripped != "[DONE]" else { return nil }
        guard let data = stripped.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }

    public static func isDone(line: String) -> Bool {
        stripDataPrefix(line).trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    private static func stripDataPrefix(_ line: String) -> String {
        if line.hasPrefix("data: ") {
            return String(line.dropFirst(6))
        } else if line.hasPrefix("data:") {
            return String(line.dropFirst(5))
        }
        return ""
    }
}

/// Streams chat completions from the DeepSeek API.
public struct DeepSeekProvider: LLMProvider {
    public let id = "deepseek"
    private let model: String
    private let apiKey: String
    private let baseURL: URL
    private let lineSource: @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>

    /// Designated initializer. `lineSource` yields raw SSE lines; injectable for testing.
    public init(model: String, apiKey: String, baseURL: URL,
                lineSource: @escaping @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>) {
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.lineSource = lineSource
    }

    /// Live initializer that talks to the real DeepSeek API over HTTP.
    public init(model: String, apiKey: String,
                baseURL: URL = URL(string: "https://api.deepseek.com")!,
                urlSession: URLSession = .shared) {
        self.init(model: model, apiKey: apiKey, baseURL: baseURL,
                  lineSource: Self.makeLiveLineSource(model: model, apiKey: apiKey,
                                                      baseURL: baseURL, session: urlSession))
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
                        if DeepSeekParser.isDone(line: line) { break }
                        if let delta = DeepSeekParser.delta(fromLine: line), !delta.isEmpty {
                            continuation.yield(delta)
                        }
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
        model: String, apiKey: String, baseURL: URL, session: URLSession
    ) -> @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error> {
        return { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var urlRequest = URLRequest(
                            url: baseURL.appendingPathComponent("chat/completions"))
                        urlRequest.httpMethod = "POST"
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        urlRequest.setValue("Bearer \(apiKey)",
                                            forHTTPHeaderField: "Authorization")
                        urlRequest.httpBody = requestBody(model: model, request: request)
                        let (bytes, response) = try await session.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            throw NSError(
                                domain: "DeepSeek", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "DeepSeek returned HTTP \(http.statusCode)."])
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
