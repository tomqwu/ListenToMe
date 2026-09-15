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

    // MARK: - Reasoning models (issue #137)

    func testParserExtractsThinkingDelta() {
        let line = #"{"message":{"role":"assistant","content":"","thinking":"Let me check"},"done":false}"#
        XCTAssertEqual(OllamaParser.thinking(fromLine: line), "Let me check")
        XCTAssertNil(OllamaParser.thinking(fromLine: #"{"message":{"content":"Hi"},"done":false}"#))
        XCTAssertNil(OllamaParser.thinking(fromLine: "not json"))
    }

    private func provider(lines: [String]) -> OllamaProvider {
        OllamaProvider(model: "m", baseURL: URL(string: "http://x")!) { _ in
            AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        }
    }

    private var probe: LLMRequest {
        LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])
    }

    func testStreamEventsSeparateThinkingFromTheAnswer() async throws {
        let provider = provider(lines: [
            #"{"message":{"role":"assistant","thinking":"Weighing options"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"Ship "},"done":false}"#,
            #"{"message":{"role":"assistant","content":"Friday."},"done":false}"#,
            #"{"done":true}"#
        ])
        var events: [LLMStreamEvent] = []
        for try await event in provider.streamEvents(probe) { events.append(event) }
        XCTAssertEqual(events, [.thinking("Weighing options"), .content("Ship "), .content("Friday.")])

        var answer = ""
        for try await delta in provider.stream(probe) { answer += delta }
        XCTAssertEqual(answer, "Ship Friday.", "reasoning is never part of the answer text")
    }

    func testThinkingOnlyResponseIsReportedAsReasoningNotAsAnEmptyAnswer() async {
        let provider = provider(lines: [
            #"{"message":{"role":"assistant","thinking":"Still reasoning"},"done":false}"#,
            #"{"done":true}"#
        ])
        do {
            for try await _ in provider.stream(probe) {}
            XCTFail("expected a failure")
        } catch let error as OllamaStreamError {
            guard case .thinkingOnly = error else { return XCTFail("expected .thinkingOnly, got \(error)") }
            XCTAssertTrue(error.localizedDescription.lowercased().contains("reasoning"),
                          error.localizedDescription)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyResponseWithoutReasoningStillReportsEmpty() async {
        let provider = provider(lines: [#"{"done":true}"#])
        do {
            for try await _ in provider.stream(probe) {}
            XCTFail("expected a failure")
        } catch let error as OllamaStreamError {
            guard case .empty = error else { return XCTFail("expected .empty, got \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testFastOptionsAreOptInAndEncodeWithoutUnsupportedCloudSchema() throws {
        let request = LLMRequest(system: "Repair", messages: [])
        let defaults = try XCTUnwrap(JSONSerialization.jsonObject(with:
            OllamaProvider.requestBody(model: "flash", request: request)) as? [String: Any])
        XCTAssertNil(defaults["think"])
        XCTAssertNil(defaults["options"])
        let fast = try XCTUnwrap(JSONSerialization.jsonObject(with:
            OllamaProvider.requestBody(model: "flash", request: request,
                                       options: .init(thinking: false, temperature: 0, maximumTokens: 700))) as? [String: Any])
        XCTAssertEqual(fast["think"] as? Bool, false)
        XCTAssertNil(fast["format"])
        let options = try XCTUnwrap(fast["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Int, 0)
        XCTAssertEqual(options["num_predict"] as? Int, 700)
    }
}
