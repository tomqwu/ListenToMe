import XCTest
@testable import ListenToMeCore

final class OpenAIContextWindowTests: XCTestCase {
    func testCapacityValidationAndOutputReserve() throws {
        XCTAssertNil(OpenAIContextWindow(tokens: 0))
        XCTAssertNil(OpenAIContextWindow(tokens: Int.max))
        let small = try XCTUnwrap(OpenAIContextWindow(tokens: 4_096))
        XCTAssertEqual(small.outputTokens(requested: nil), 1_024)
        XCTAssertEqual(small.outputTokens(requested: 512), 512)
        XCTAssertEqual(small.outputTokens(requested: 0), 1)
        XCTAssertEqual(small.maxPromptCharacters, 1_792)
        for capacity in OpenAIContextWindow.choices {
            XCTAssertNotNil(OpenAIContextWindow(tokens: capacity))
        }
    }

    func testCompleteRequestIncludesSystemMessagesUnicodeAndFraming() throws {
        let window = try XCTUnwrap(OpenAIContextWindow(tokens: 4_096))
        let request = { (system: String, user: String) in
            LLMRequest(system: system, messages: [ChatMessage(role: "user", content: user)])
        }
        try window.validate(request("s", String(repeating: "a", count: 1_791)), requestedOutput: nil)
        XCTAssertThrowsError(try window.validate(request("s", String(repeating: "a", count: 1_792)), requestedOutput: nil))
        XCTAssertThrowsError(try window.validate(request(String(repeating: "x", count: 2_000), "short"), requestedOutput: nil))
        XCTAssertThrowsError(try window.validate(request("s", String(repeating: "中", count: 600)), requestedOutput: nil))
        XCTAssertThrowsError(try window.validate(request("s", String(repeating: "👩🏽‍💻", count: 200)), requestedOutput: nil))
        let many = LLMRequest(system: "", messages: (0..<20).map { _ in ChatMessage(role: "user", content: "") })
        XCTAssertThrowsError(try window.validate(many, requestedOutput: nil))
    }

    func testCharacterTrimmingHintLeavesRoomForOrdinaryMessageFraming() throws {
        let window = try XCTUnwrap(OpenAIContextWindow(tokens: 4_096))
        let system = "Summarize the conversation."
        let allocation = PromptBudget.allocate(limit: window.maxPromptCharacters, scaffold: system.count,
                                                transcript: 20_000, references: 0)
        let request = LLMRequest(system: system, messages: [
            ChatMessage(role: "user", content: String(repeating: "a", count: allocation.transcript))
        ])
        XCTAssertLessThan(allocation.transcript, 20_000)
        try window.validate(request, requestedOutput: nil)
        // Even a caller using the complete hint without PromptBudget's extra reserve fits.
        try window.validate(LLMRequest(system: system, messages: [ChatMessage(role: "user", content:
            String(repeating: "a", count: window.maxPromptCharacters - system.count))]), requestedOutput: nil)
    }

    func testRequestBodyCapsAnswerForChatAndQuickWithoutChangingUnknownServers() throws {
        let window = try XCTUnwrap(OpenAIContextWindow(tokens: 4_096))
        for purpose in [LLMRequest.Purpose.chat, .quickEvaluation] {
            let request = LLMRequest(system: "s", messages: [], purpose: purpose)
            let data = OpenAICompatibleProvider.requestBody(model: "m", request: request, contextWindow: window)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["max_tokens"] as? Int, 1_024)
        }
        let data = OpenAICompatibleProvider.requestBody(model: "m", request: LLMRequest(system: "s", messages: []))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(body["max_tokens"])
    }

    func testOversizedRequestNeverReachesTransport() async throws {
        defer { OpenAIStubProtocol.reset() }
        let provider = OpenAICompatibleProvider(model: "m", baseURL: URL(string: "https://example.com/v1")!,
                                               urlSession: OpenAIStubProtocol.session(),
                                               contextWindow: OpenAIContextWindow(tokens: 4_096))
        do {
            for try await _ in provider.stream(LLMRequest(system: "s", messages: [
                ChatMessage(role: "user", content: String(repeating: "private", count: 1_000))
            ])) {}
            XCTFail("Expected a local context failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No text was sent"))
        }
        XCTAssertTrue(OpenAIStubProtocol.received.isEmpty)
    }
}
