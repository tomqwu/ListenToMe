import XCTest
@testable import ListenToMeCore

final class AIHardeningTests: XCTestCase {
    func testLocalMetadataFailsClosedForCloudUnknownAndMalformedModels() {
        for json in ["{}", "invalid", #"{"details":{"format":"gguf"}}"#,
                     #"{"remote_host":"https://ollama.com","details":{"format":"gguf"},"model_info":{"a":1}}"#,
                     #"{"remote_model":"cloud","details":{"format":"gguf"},"model_info":{"a":1}}"#] {
            XCTAssertFalse(ModelPrivacy.isVerifiedLocal(Data(json.utf8)), json)
        }
        XCTAssertTrue(ModelPrivacy.isVerifiedLocal(Data(
            #"{"details":{"format":"gguf"},"model_info":{"architecture":"qwen"}}"#.utf8)))
        XCTAssertEqual(AIProcessingMode.allCases.map(\.label).count, 3)
    }

    func testInBandErrorPreservesPartialTextAndThrows() async {
        let result = await stream([#"{"message":{"content":"Partial"},"done":false}"#,
                                   #"{"error":"model unavailable"}"#])
        XCTAssertEqual(result.text, "Partial")
        XCTAssertTrue(result.error?.contains("model unavailable") == true)
    }

    func testPrematureEndAndEmptyCompletionAreErrors() async {
        let incomplete = await stream([#"{"message":{"content":"Partial"},"done":false}"#])
        XCTAssertTrue(incomplete.error?.contains("before completion") == true)
        let empty = await stream([#"{"done":true}"#])
        XCTAssertTrue(empty.error?.contains("without an answer") == true)
    }

    func testFinalFrameContentIsNotLost() async {
        let result = await stream([#"{"message":{"content":"Final"},"done":true}"#])
        XCTAssertEqual(result.text, "Final"); XCTAssertNil(result.error)
    }

    private func stream(_ lines: [String]) async -> (text: String, error: String?) {
        let provider = OllamaProvider(model: "fixture", baseURL: URL(string: "http://localhost")!) { _ in
            AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        }
        var text = ""
        do {
            for try await delta in provider.stream(LLMRequest(system: "", messages: [])) { text += delta }
            return (text, nil)
        } catch { return (text, error.localizedDescription) }
    }

    func testLocalModeChecksMetadataBeforeSendingConversation() async throws {
        for isLocal in [false, true] {
            var paths: [String] = []
            StubURLProtocol.handler = { request in
                paths.append(request.url!.path)
                let data: String
                if request.url!.path == "/api/show" {
                    data = isLocal ? #"{"details":{"format":"gguf"},"model_info":{"arch":"qwen"}}"#
                        : #"{"remote_host":"https://ollama.com"}"#
                } else { data = #"{"message":{"content":"OK"},"done":true}"# }
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(data.utf8))
            }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel(); StubURLProtocol.handler = nil }
            let provider = OllamaProvider(model: "fixture", baseURL: URL(string: "http://localhost:11434")!,
                                          urlSession: session, localOnly: true)
            var error: Error?
            do { for try await _ in provider.stream(LLMRequest(system: "private meeting", messages: [])) {} }
            catch let failure { error = failure }
            XCTAssertEqual(paths, isLocal ? ["/api/show", "/api/chat"] : ["/api/show"])
            XCTAssertEqual(error == nil, isLocal)
        }
    }

    func testLocalModeRejectsNonLoopbackEndpointBeforeAnyRequest() async {
        let provider = OllamaProvider(model: "fixture", baseURL: URL(string: "https://ollama.com")!, localOnly: true)
        do {
            for try await _ in provider.stream(LLMRequest(system: "private", messages: [])) {}
            XCTFail("Remote endpoint must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("requires a local")) }
    }
}
