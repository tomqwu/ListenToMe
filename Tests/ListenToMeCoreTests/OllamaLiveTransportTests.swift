import XCTest
@testable import ListenToMeCore

// MARK: - URLProtocol stub

/// A URLProtocol subclass that intercepts all requests and returns canned responses.
/// Uses `nonisolated(unsafe)` static mutable state so it is safe under Swift 6 strict
/// concurrency, given that tests set the handler before making any URLSession calls.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Per-test handler. Set this before creating the session / provider.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self,
                didFailWithError: NSError(domain: "StubURLProtocol", code: -1,
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

// MARK: - Helper

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeProvider(model: String = "testModel",
                          baseURL: URL = URL(string: "http://stub.local")!,
                          apiKey: String? = nil,
                          session: URLSession) -> OllamaProvider {
    OllamaProvider(model: model, baseURL: baseURL, apiKey: apiKey, urlSession: session)
}

private func sampleRequest() -> LLMRequest {
    LLMRequest(system: "sys", messages: [ChatMessage(role: "user", content: "hello")])
}

// MARK: - Tests

final class OllamaLiveTransportTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: 1. 2xx streaming success

    func testLivePathYieldsDeltasFrom200Response() async throws {
        let ndjson = [
            #"{"message":{"role":"assistant","content":"Hel"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"lo"},"done":false}"#,
            #"{"done":true}"#,
        ].joined(separator: "\n")

        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/api/chat")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/x-ndjson"])!
            return (response, Data(ndjson.utf8))
        }

        let provider = makeProvider(session: makeStubSession())
        var collected = ""
        for try await delta in provider.stream(sampleRequest()) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello")
    }

    // MARK: 2. non-2xx → stream throws

    private func streamFailureMessage(status: Int, body: String) async -> String? {
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/api/chat")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let provider = makeProvider(session: makeStubSession())
        do {
            for try await _ in provider.stream(sampleRequest()) {}
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func testLivePathThrowsOnNon2xxResponse() async throws {
        let raw = await streamFailureMessage(status: 404, body: "")
        let message = try XCTUnwrap(raw)
        XCTAssertTrue(message.contains("HTTP 404"), message)
    }

    /// Issue #118: the server's own explanation must reach the pane instead of a canned guess.
    func testLivePathSurfacesTheServerErrorBody() async throws {
        let raw = await streamFailureMessage(status: 400, body: #"{"error":"unsupported option think"}"#)
        let message = try XCTUnwrap(raw)
        XCTAssertTrue(message.contains("HTTP 400"), message)
        XCTAssertTrue(message.contains("unsupported option think"), message)
    }

    func testLivePathReportsRejectedKeyOn401NotAMissingModel() async throws {
        let raw = await streamFailureMessage(status: 401, body: #"{"error":"unauthorized"}"#)
        let message = try XCTUnwrap(raw)
        XCTAssertTrue(message.lowercased().contains("api key"), message)
        XCTAssertFalse(message.contains("model pulled"), message)
        XCTAssertTrue(message.contains("unauthorized"), message)
    }

    func testLivePathReportsRateLimitOn429() async throws {
        let raw = await streamFailureMessage(status: 429, body: "")
        let message = try XCTUnwrap(raw)
        XCTAssertTrue(message.lowercased().contains("rate"), message)
        XCTAssertFalse(message.contains("model pulled"), message)
    }

    // MARK: 3. Authorization header is set when apiKey is provided

    func testLivePathSendsAuthorizationHeaderWhenApiKeySet() async throws {
        let expectedKey = "test-secret-key"
        var capturedRequest: URLRequest?

        let ndjson = #"{"message":{"content":"OK"},"done":true}"#
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/api/chat")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(ndjson.utf8))
        }

        let provider = makeProvider(apiKey: expectedKey, session: makeStubSession())
        for try await _ in provider.stream(sampleRequest()) {}

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedKey)")
    }

    func testLivePathOmitsAuthorizationHeaderWhenApiKeyIsNil() async throws {
        var capturedRequest: URLRequest?

        let ndjson = #"{"message":{"content":"OK"},"done":true}"#
        StubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/api/chat")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(ndjson.utf8))
        }

        let provider = makeProvider(apiKey: nil, session: makeStubSession())
        for try await _ in provider.stream(sampleRequest()) {}

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: 4. Request body contains the model name

    func testLivePathSendsModelInRequestBody() async throws {
        let expectedModel = "llama3.1"
        var capturedBody: Data?

        let ndjson = #"{"message":{"content":"OK"},"done":true}"#
        StubURLProtocol.handler = { request in
            // URLSession may pass the body via httpBodyStream instead of httpBody
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
                url: URL(string: "http://stub.local/api/chat")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (response, Data(ndjson.utf8))
        }

        let provider = makeProvider(model: expectedModel, session: makeStubSession())
        // drain stream so the request is actually made
        for try await _ in provider.stream(sampleRequest()) {}

        let body = try XCTUnwrap(capturedBody)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, expectedModel)
    }
}
