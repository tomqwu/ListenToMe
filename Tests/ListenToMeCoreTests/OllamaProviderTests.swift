import XCTest
@testable import ListenToMeCore

final class OllamaProviderTests: XCTestCase {
    func testParserExtractsContentDelta() {
        let line = #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#
        XCTAssertEqual(OllamaParser.delta(fromLine: line), "Hello")
    }

    func testParserReturnsNilForNonContentLine() {
        XCTAssertNil(OllamaParser.delta(fromLine: #"{"done":true}"#))
        XCTAssertNil(OllamaParser.delta(fromLine: "not json"))
    }

    func testParserDetectsDone() {
        XCTAssertTrue(OllamaParser.isDone(line: #"{"done":true}"#))
        XCTAssertFalse(OllamaParser.isDone(line: #"{"done":false}"#))
        XCTAssertFalse(OllamaParser.isDone(line: "garbage"))
    }

    func testRequestBodyEncodesModelMessagesAndStream() throws {
        let req = LLMRequest(system: "SYS", messages: [ChatMessage(role: "user", content: "hi")])
        let data = OllamaProvider.requestBody(model: "llama3.1", request: req)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "llama3.1")
        XCTAssertEqual(obj["stream"] as? Bool, true)
        let messages = try XCTUnwrap(obj["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.first?["content"], "SYS")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "hi")
    }

    func testStreamYieldsParsedDeltasUntilDone() async throws {
        let lines = [
            #"{"message":{"role":"assistant","content":"Hel"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"lo"},"done":false}"#,
            #"{"done":true}"#,
            #"{"message":{"role":"assistant","content":"IGNORED"},"done":false}"#
        ]
        let provider = OllamaProvider(model: "m", baseURL: URL(string: "http://x")!) { _ in
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
}
