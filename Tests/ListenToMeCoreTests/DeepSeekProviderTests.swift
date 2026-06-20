import XCTest
@testable import ListenToMeCore

// MARK: - URLProtocol stub

/// A URLProtocol subclass that intercepts all requests and returns canned responses.
/// Uses `nonisolated(unsafe)` static mutable state so it is safe under Swift 6 strict
/// concurrency, given that tests set the handler before making any URLSession calls.
final class DeepSeekStubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Per-test handler. Set this before creating the session / provider.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = DeepSeekStubURLProtocol.handler else {
            client?.urlProtocol(self,
                didFailWithError: NSError(domain: "DeepSeekStubURLProtocol", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeDeepSeekStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DeepSeekStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeDeepSeekProvider(
    model: String = "deepseek-chat",
    apiKey: String = "test-key",
    baseURL: URL = URL(string: "http://stub.local")!,
    session: URLSession
) -> DeepSeekProvider {
    DeepSeekProvider(model: model, apiKey: apiKey, baseURL: baseURL, urlSession: session)
}

private func deepSeekSampleRequest() -> LLMRequest {
    LLMRequest(system: "sys", messages: [ChatMessage(role: "user", content: "hello")])
}

// MARK: - Tests

final class DeepSeekProviderTests: XCTestCase {
    override func tearDown() {
        DeepSeekStubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: 1. Parser extracts delta content

    func testParserExtractsDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(DeepSeekParser.delta(fromLine: line), "Hello")
    }

    // MARK: 2. Parser returns nil for [DONE], non-json, and no delta content

    func testParserReturnsNilForDone() {
        XCTAssertNil(DeepSeekParser.delta(fromLine: "data: [DONE]"))
    }

    func testParserReturnsNilForNonJson() {
        XCTAssertNil(DeepSeekParser.delta(fromLine: "data: not-json"))
    }

    func testParserReturnsNilForNoDeltaContent() {
        let line = #"data: {"choices":[{"delta":{}}]}"#
        XCTAssertNil(DeepSeekParser.delta(fromLine: line))
    }

    // MARK: 3. isDone

    func testIsDoneTrueForDoneLine() {
        XCTAssertTrue(DeepSeekParser.isDone(line: "data: [DONE]"))
        XCTAssertTrue(DeepSeekParser.isDone(line: "data:[DONE]"))
    }

    func testIsDoneFalseForOtherLines() {
        XCTAssertFalse(DeepSeekParser.isDone(line: #"data: {"choices":[]}"#))
        XCTAssertFalse(DeepSeekParser.isDone(line: ""))
        XCTAssertFalse(DeepSeekParser.isDone(line: "garbage"))
    }

    // MARK: 4. requestBody encodes model, stream, system + user messages

    func testRequestBodyEncodesModelMessagesAndStream() throws {
        let req = LLMRequest(system: "SYS", messages: [ChatMessage(role: "user", content: "hi")])
        let data = DeepSeekProvider.requestBody(model: "deepseek-chat", request: req)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "deepseek-chat")
        XCTAssertEqual(obj["stream"] as? Bool, true)
        let messages = try XCTUnwrap(obj["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.first?["content"], "SYS")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "hi")
    }

    // MARK: 5. stream yields deltas from injected lineSource, stops at [DONE]

    func testStreamYieldsDeltasAndStopsAtDone() async throws {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"IGNORED"}}]}"#
        ]
        let provider = DeepSeekProvider(
            model: "m", apiKey: "key",
            baseURL: URL(string: "http://x")!
        ) { _ in
            AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        }
        var collected = ""
        for try await delta in provider.stream(
            LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello")
    }

    // MARK: 6a. Live transport: HTTP 200 with SSE body → concatenated deltas

    func testLivePathYieldsDeltasFrom200Response() async throws {
        let sseBody = [
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            "data: [DONE]"
        ].joined(separator: "\n")

        DeepSeekStubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"])!
            return (response, Data(sseBody.utf8))
        }

        let provider = makeDeepSeekProvider(session: makeDeepSeekStubSession())
        var collected = ""
        for try await delta in provider.stream(deepSeekSampleRequest()) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello")
    }

    // MARK: 6b. Live transport: HTTP 401 → stream throws

    func testLivePathThrowsOnNon2xxResponse() async throws {
        DeepSeekStubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data())
        }

        let provider = makeDeepSeekProvider(session: makeDeepSeekStubSession())
        var thrownError: Error?
        do {
            for try await _ in provider.stream(deepSeekSampleRequest()) {}
        } catch {
            thrownError = error
        }
        let err = try XCTUnwrap(thrownError as? NSError)
        XCTAssertEqual(err.domain, "DeepSeek")
        XCTAssertEqual(err.code, 401)
    }

    // MARK: 7. Live request carries Authorization: Bearer <key> header

    func testLiveRequestCarriesBearerAuthHeader() async throws {
        let expectedKey = "sk-test-secret"
        var capturedRequest: URLRequest?

        let sseBody = "data: [DONE]"
        DeepSeekStubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(sseBody.utf8))
        }

        let provider = makeDeepSeekProvider(apiKey: expectedKey, session: makeDeepSeekStubSession())
        for try await _ in provider.stream(deepSeekSampleRequest()) {}

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedKey)")
    }

    // MARK: 8. Live request body contains model name (reads via httpBodyStream)

    func testLivePathSendsModelInRequestBody() async throws {
        let expectedModel = "deepseek-coder"
        var capturedBody: Data?

        let sseBody = "data: [DONE]"
        DeepSeekStubURLProtocol.handler = { request in
            if let data = request.httpBody {
                capturedBody = data
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let bytesRead = stream.read(buffer, maxLength: bufferSize)
                    if bytesRead > 0 {
                        data.append(buffer, count: bytesRead)
                    }
                }
                stream.close()
                capturedBody = data
            }
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(sseBody.utf8))
        }

        let provider = makeDeepSeekProvider(model: expectedModel, session: makeDeepSeekStubSession())
        for try await _ in provider.stream(deepSeekSampleRequest()) {}

        let body = try XCTUnwrap(capturedBody)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, expectedModel)
    }
}
