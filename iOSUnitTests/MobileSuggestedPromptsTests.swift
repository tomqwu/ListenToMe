import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Answers every request with a fixed response and records what it was asked.
private final class SuggestionStub: LLMProvider, @unchecked Sendable {
    let id = "suggestion-stub"
    var response: String
    private(set) var requests: [LLMRequest] = []
    init(response: String) { self.response = response }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        let response = response
        return AsyncThrowingStream { continuation in continuation.yield(response); continuation.finish() }
    }
}

/// Context-aware "Suggested" chips on iOS (#61): they ride on the manual Quick pass the user asked
/// for, a tap reaches Deep literally, and stale chips are cleared. No real model is called.
@MainActor
final class MobileSuggestedPromptsTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testManualQuickOnAJSONModelOffersItsSuggestions() async {
        let stub = SuggestionStub(response: #"{"action":"publish","context":"Pricing","bullets":["Pricing is open."],"#
            + #""reviews":[],"suggestions":["Summarize pricing options","{junk}"]}"#)
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        session.notes = "Pricing is still open."
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "- Pricing is open.")
        XCTAssertEqual(session.suggestedPrompts, ["Summarize pricing options"])
        XCTAssertEqual(stub.requests.count, 1, "The chips cost no extra request")
    }

    func testAppleProseQuickReadsTheStrictSuggestedBlockAndNothingElse() async {
        let onDevice = SuggestionStub(response: "- Sam owns the proposal.\nSuggested:\n> Draft a reply to Sam\n> none")
        let session = MobileSession(storageDirectory: root)
        session.onDeviceProviderOverride = onDevice
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .apple
        session.notes = "Sam will send the proposal."
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "- Sam owns the proposal.", "Chips are never shown as takeaways")
        XCTAssertEqual(session.suggestedPrompts, ["Draft a reply to Sam"])
        XCTAssertTrue(onDevice.requests.first?.system.contains(SuggestedPrompts.proseInstructions) ?? false)

        onDevice.response = "- Sam owns the proposal.\n> Draft a reply to Sam"
        session.newConversation()
        session.notes = "Sam will send the proposal."
        await session.summarize(mode: .quick)
        XCTAssertTrue(session.suggestedPrompts.isEmpty, "No heading, no chips")
    }

    func testATapSendsTheLiteralRequestThroughDeepAndConsumesTheChip() async throws {
        let stub = SuggestionStub(response: "Nobody owns it yet.")
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        session.notes = "Who owns the Thursday review?"
        session.quickReader.offerSuggestions(["Who owns the Thursday review?", "Draft a reminder"])
        session.askSuggested("Who owns the Thursday review?")
        XCTAssertEqual(session.suggestedPrompts, ["Draft a reminder"])
        try await waitUntil { !session.deepThought.isEmpty }
        let request = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(request.system, MobileSummaryMode.deep.instructions)
        let user = request.messages.last?.content ?? ""
        XCTAssertTrue(user.hasPrefix(PromptData.block("transcript", session.summarySource)))
        XCTAssertTrue(user.hasSuffix(PromptBuilder.askInstruction("Who owns the Thursday review?")))
        XCTAssertEqual(session.deepThought, "**Who owns the Thursday review?**\n\nNobody owns it yet.")
    }

    func testABlockedTapSendsNothingAndKeepsTheChip() {
        let stub = SuggestionStub(response: "unused")
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        session.quickReader.offerSuggestions(["Draft a reminder"])
        XCTAssertNotNil(session.suggestionBlockReason, "Nothing to answer from yet")
        session.askSuggested("Draft a reminder")
        XCTAssertEqual(session.suggestedPrompts, ["Draft a reminder"])
        XCTAssertNotNil(session.message)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testProviderChangeAndNewConversationClearChips() {
        let session = MobileSession(storageDirectory: root, summaryProvider: SuggestionStub(response: ""))
        session.quickReader.offerSuggestions(["Draft a reminder"])
        session.ai.quickSettingsChanged?()
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
        session.quickReader.offerSuggestions(["Draft a reminder"])
        session.newConversation()
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}
