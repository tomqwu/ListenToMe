import XCTest
@testable import ListenToMeCore

final class OllamaContextWindowTests: XCTestCase {
    private func metadata(limit: Int = 65_536) -> Data {
        Data("{\"details\":{\"format\":\"gguf\"},\"model_info\":{\"general.architecture\":\"qwen\",\"qwen.context_length\":\(limit)}}".utf8)
    }

    func testBucketsIncludeAllMessagesUnicodeAndOutput() throws {
        let short = LLMRequest(system: "System", messages: [.init(role: "user", content: "Hello")])
        XCTAssertEqual(try OllamaContextWindow.allocate(metadata: metadata(), request: short).contextTokens, 8_192)
        for capacity in [2_048, 4_096] {
            let small = try OllamaContextWindow.allocate(metadata: metadata(limit: capacity), request: short)
            XCTAssertEqual(small.contextTokens, capacity)
            XCTAssertEqual(small.outputTokens, capacity / 4)
        }
        let deep = LLMRequest(system: "Keep the opening", messages: [
            .init(role: "user", content: String(repeating: "x", count: 32_000)),
            .init(role: "assistant", content: "Earlier answer")])
        let allocation = try OllamaContextWindow.allocate(metadata: metadata(limit: 40_960), request: deep)
        XCTAssertEqual(allocation.contextTokens, 40_960)
        XCTAssertEqual(allocation.outputTokens, 4_096)
        let chinese = LLMRequest(system: "", messages: [.init(role: "user", content: String(repeating: "中", count: 5_000))])
        XCTAssertEqual(try OllamaContextWindow.allocate(metadata: metadata(), request: chinese).contextTokens, 32_768)
        let quick = try OllamaContextWindow.allocate(metadata: metadata(), request: short, maximumTokens: 3_072)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: OllamaProvider.requestBody(
            model: "test", request: short, options: .init(thinking: false), context: quick)) as? [String: Any])
        XCTAssertEqual((body["options"] as? [String: Int])?["num_ctx"], 8_192)
        XCTAssertEqual((body["options"] as? [String: Int])?["num_predict"], 3_072)
        XCTAssertEqual(body["think"] as? Bool, false)
    }

    func testRejectsUnknownCapacityOversizeAndUnboundedOutput() throws {
        let request = LLMRequest(system: "", messages: [])
        XCTAssertThrowsError(try OllamaContextWindow.allocate(metadata: Data("{}".utf8), request: request))
        XCTAssertThrowsError(try OllamaContextWindow.allocate(metadata: metadata(), request: request, maximumTokens: -1))
        let huge = LLMRequest(system: String(repeating: "x", count: 70_000), messages: [])
        XCTAssertThrowsError(try OllamaContextWindow.allocate(metadata: metadata(limit: 131_072), request: huge)) {
            XCTAssertTrue($0.localizedDescription.contains("No text was sent"))
        }
    }

    func testLocalHTTPContractSizesDeepPromptAndRejectsOversizeBeforeChat() async throws {
        var chatBodies: [[String: Any]] = []
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/show" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.metadata(limit: 40_960))
            }
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; data.append(buffer, count: count)
                }
            }
            chatBodies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"message":{"content":"Opening preserved"},"done":true}"#.utf8))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
        let provider = OllamaProvider(model: "fixture", urlSession: session, localOnly: true)
        let text = "Opening secret is blue. " + String(repeating: "x", count: 32_000)
        for try await _ in provider.stream(LLMRequest(system: "Read the whole input", messages: [.init(role: "user", content: text)])) {}
        XCTAssertEqual(chatBodies.count, 1)
        XCTAssertEqual((chatBodies[0]["options"] as? [String: Int])?["num_ctx"], 40_960)
        XCTAssertEqual((chatBodies[0]["messages"] as? [[String: String]])?.last?["content"], text)
        do {
            for try await _ in provider.stream(LLMRequest(system: String(repeating: "x", count: 50_000), messages: [])) {}
            XCTFail("Oversize requests must not reach chat")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No text was sent")) }
        XCTAssertEqual(chatBodies.count, 1)
    }
    func testCloudModelsKeepServerManagedContext() async throws {
        var paths: [String] = []
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            let payload = request.url!.path == "/api/show"
                ? #"{"remote_host":"https://ollama.com","remote_model":"cloud"}"#
                : #"{"message":{"content":"Cloud answer"},"done":true}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(payload.utf8))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
        for manage in [false, true] {
            paths = []
            let provider = OllamaProvider(model: "cloud", baseURL: URL(string: "https://example.test")!,
                                          urlSession: session, manageContext: manage)
            for try await _ in provider.stream(LLMRequest(system: "", messages: [])) {}
            XCTAssertEqual(paths, manage ? ["/api/show", "/api/chat"] : ["/api/chat"])
        }
    }

    func testUnknownMetadataStopsCustomEndpointBeforeSendingText() async throws {
        var paths: [String] = []
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
        let provider = OllamaProvider(model: "unknown", baseURL: URL(string: "http://server.local:11434")!,
                                      urlSession: session, manageContext: true)
        do {
            for try await _ in provider.stream(LLMRequest(system: "private text", messages: [])) {}
            XCTFail("Unknown model capacity must not bypass context protection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("metadata is incomplete")) }
        XCTAssertEqual(paths, ["/api/show"])
    }

}
