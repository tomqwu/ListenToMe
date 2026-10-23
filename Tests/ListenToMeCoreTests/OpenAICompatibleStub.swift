import Foundation
@testable import ListenToMeCore

/// URLProtocol stub for the OpenAI-compatible contract tests. Separate from `StubURLProtocol` so the
/// two suites never share a handler.
final class OpenAIStubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case response(status: Int, headers: [String: String], body: Data)
        case redirect(status: Int, location: String)
        case failure(URLError.Code)
    }

    nonisolated(unsafe) static var reply: ((URLRequest) -> Reply)?
    /// Every request that reached the stub, with its body read from the stream.
    nonisolated(unsafe) static var received: [(request: URLRequest, body: Data)] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.received.append((request, Self.body(of: request)))
        guard let reply = Self.reply?(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch reply {
        case let .response(status, headers, body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .redirect(status, location):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": location])!
            let next = URLRequest(url: URL(string: location, relativeTo: url)!)
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    static func reset() { reply = nil; received = [] }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func sse(_ lines: [String], status: Int = 200,
                    contentType: String = "text/event-stream") -> (URLRequest) -> Reply {
        let body = Data(lines.joined(separator: "\n").utf8)
        return { _ in .response(status: status, headers: ["Content-Type": contentType], body: body) }
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

func chunk(_ content: String? = nil, reasoning: String? = nil, finish: String? = nil) -> String {
    var delta: [String: Any] = [:]
    if let content { delta["content"] = content }
    if let reasoning { delta["reasoning_content"] = reasoning }
    var choice: [String: Any] = ["index": 0, "delta": delta]
    choice["finish_reason"] = finish ?? NSNull()
    let object: [String: Any] = ["id": "c1", "object": "chat.completion.chunk", "choices": [choice]]
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    return "data: " + String(decoding: data, as: UTF8.self)
}
