import XCTest
@testable import ListenToMeCore

// MARK: - URLProtocol stub

/// A URLProtocol subclass that intercepts all requests and returns canned responses.
/// Uses `nonisolated(unsafe)` static mutable state so it is safe under Swift 6 strict
/// concurrency, given that tests set the handler before making any URLSession calls.
final class OpenAICompatibleStubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Per-test handler. Set this before creating the session / provider.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = OpenAICompatibleStubURLProtocol.handler else {
            client?.urlProtocol(self,
                didFailWithError: NSError(domain: "OpenAICompatibleStubURLProtocol", code: -1,
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

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OpenAICompatibleStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeProvider(
    model: String = "test-model",
    apiKey: String? = "test-key",
    baseURL: URL = URL(string: "http://stub.local")!,
    session: URLSession
) -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(model: model, apiKey: apiKey, baseURL: baseURL, urlSession: session)
}

private func sampleRequest() -> LLMRequest {
    LLMRequest(system: "sys", messages: [ChatMessage(role: "user", content: "hello")])
}

// MARK: - Tests

final class OpenAICompatibleProviderTests: XCTestCase {
    override func tearDown() {
        OpenAICompatibleStubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: 1. Parser extracts delta content

    func testParserExtractsDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(OpenAICompatibleParser.delta(fromLine: line), "Hello")
    }

    // MARK: 2. Parser returns nil for [DONE], non-json, and no delta content

    func testParserReturnsNilForDone() {
        XCTAssertNil(OpenAICompatibleParser.delta(fromLine: "data: [DONE]"))
    }

    func testParserReturnsNilForNonJson() {
        XCTAssertNil(OpenAICompatibleParser.delta(fromLine: "data: not-json"))
    }

    func testParserReturnsNilForNoDeltaContent() {
        let line = #"data: {"choices":[{"delta":{}}]}"#
        XCTAssertNil(OpenAICompatibleParser.delta(fromLine: line))
    }

    // MARK: 3. isDone

    func testIsDoneTrueForDoneLine() {
        XCTAssertTrue(OpenAICompatibleParser.isDone(line: "data: [DONE]"))
        XCTAssertTrue(OpenAICompatibleParser.isDone(line: "data:[DONE]"))
    }

    func testIsDoneFalseForOtherLines() {
        XCTAssertFalse(OpenAICompatibleParser.isDone(line: #"data: {"choices":[]}"#))
        XCTAssertFalse(OpenAICompatibleParser.isDone(line: ""))
        XCTAssertFalse(OpenAICompatibleParser.isDone(line: "garbage"))
    }

    // MARK: 4. requestBody encodes model, stream, system + user messages

    func testRequestBodyEncodesModelMessagesAndStream() throws {
        let req = LLMRequest(system: "SYS", messages: [ChatMessage(role: "user", content: "hi")])
        let data = OpenAICompatibleProvider.requestBody(model: "deepseek-v4-flash", request: req)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "deepseek-v4-flash")
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
        let provider = OpenAICompatibleProvider(
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

        OpenAICompatibleStubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"])!
            return (response, Data(sseBody.utf8))
        }

        let provider = makeProvider(session: makeStubSession())
        var collected = ""
        for try await delta in provider.stream(sampleRequest()) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello")
    }

    // MARK: 6b. Live transport: HTTP 401 → stream throws

    func testLivePathThrowsOnNon2xxResponse() async throws {
        OpenAICompatibleStubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data())
        }

        let provider = makeProvider(session: makeStubSession())
        var thrownError: Error?
        do {
            for try await _ in provider.stream(sampleRequest()) {}
        } catch {
            thrownError = error
        }
        let err = try XCTUnwrap(thrownError as? NSError)
        XCTAssertEqual(err.domain, "OpenAICompatible")
        XCTAssertEqual(err.code, 401)
    }

    // MARK: 7. Live request carries Authorization: Bearer <key> header

    func testLiveRequestCarriesBearerAuthHeader() async throws {
        let expectedKey = "sk-test-secret"
        var capturedRequest: URLRequest?

        let sseBody = "data: [DONE]"
        OpenAICompatibleStubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(sseBody.utf8))
        }

        let provider = makeProvider(apiKey: expectedKey, session: makeStubSession())
        for try await _ in provider.stream(sampleRequest()) {}

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedKey)")
    }

    // MARK: 9. No apiKey → no Authorization header (local servers need none)

    func testLiveRequestOmitsAuthWhenNoKey() async throws {
        var capturedRequest: URLRequest?
        OpenAICompatibleStubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("data: [DONE]".utf8))
        }
        let provider = makeProvider(apiKey: nil, session: makeStubSession())
        for try await _ in provider.stream(sampleRequest()) {}
        let req = try XCTUnwrap(capturedRequest)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: 8. Live request body contains model name (reads via httpBodyStream)

    func testLivePathSendsModelInRequestBody() async throws {
        let expectedModel = "deepseek-coder"
        var capturedBody: Data?

        let sseBody = "data: [DONE]"
        OpenAICompatibleStubURLProtocol.handler = { request in
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

        let provider = makeProvider(model: expectedModel, session: makeStubSession())
        for try await _ in provider.stream(sampleRequest()) {}

        let body = try XCTUnwrap(capturedBody)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, expectedModel)
    }
}
