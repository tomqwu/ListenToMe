import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Answers every request with a fixed response (or a failure) and records what it was asked.
/// `onStream` runs synchronously when a request starts, so a test can change settings mid-request.
private final class SuggestionStub: LLMProvider, @unchecked Sendable {
    let id = "suggestion-stub"
    var response: String
    var failure: (any Error)?
    var onStream: (() -> Void)?
    private(set) var requests: [LLMRequest] = []
    init(response: String, failure: (any Error)? = nil) { self.response = response; self.failure = failure }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        onStream?()
        let response = response, failure = failure
        return AsyncThrowingStream { continuation in
            if let failure { continuation.finish(throwing: failure) } else {
                continuation.yield(response); continuation.finish()
            }
        }
    }
}

/// Context-aware "Suggested" chips on iOS (#61): they ride on the manual Quick pass the user asked
/// for, a tap is a separate ask that never becomes the Deep review, and stale chips are cleared.
/// No real model is called.
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

    func testAppleProseQuickReadsOnlyAFinalSuggestedBlock() async {
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

        onDevice.response = "Suggested:\n> Draft a reply to Sam\n- Sam owns the proposal.\n- 2025 budget approved"
        session.newConversation()
        session.notes = "Sam will send the proposal."
        await session.summarize(mode: .quick)
        XCTAssertTrue(session.suggestedPrompts.isEmpty, "A heading that is not the final section gives no chips")
        XCTAssertEqual(session.quickSummary, "- Sam owns the proposal.\n- 2025 budget approved")
    }

    /// Review finding: a chip answer used to replace Deep Summary, its saved text and Auto's Deep
    /// review state. It is now a separate ask, answered in the Ask card under Quick (#235 removes Deep).
    func testATapIsASeparateAskThatLeavesEverySummaryAndReviewStateAlone() async throws {
        let stub = SuggestionStub(response: "Nobody owns it yet.")
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        session.notes = "Who owns the Thursday review?"
        session.quickSummary = "- Review on Thursday."
        session.deepThought = "Existing Deep analysis."
        session.save(announce: false)
        session.quickReader.offerSuggestions(["Who owns the Thursday review?", "Draft a reminder"])

        XCTAssertTrue(session.askSuggested("Who owns the Thursday review?"))
        XCTAssertEqual(session.suggestedPrompts, ["Who owns the Thursday review?", "Draft a reminder"],
                       "A chip is used up only once its answer arrived")
        await session.suggestedAsk.waitForAnswer()

        let request = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(request.system, MobileSession.askSystem)
        XCTAssertEqual(request.purpose, .chat)
        let user = request.messages.last?.content ?? ""
        XCTAssertTrue(user.hasPrefix("<transcript>\nNotes: Who owns the Thursday review?"), user)
        let instruction = PromptBuilder.askInstruction("Who owns the Thursday review?") + " Answer briefly."
        XCTAssertTrue(user.hasSuffix(instruction))
        XCTAssertEqual(session.suggestedAsk.question, "Who owns the Thursday review?")
        XCTAssertEqual(session.suggestedAsk.answer, "Nobody owns it yet.")
        XCTAssertEqual(session.suggestedPrompts, ["Draft a reminder"])
        XCTAssertEqual(session.quickSummary, "- Review on Thursday.")
        XCTAssertEqual(session.deepThought, "Existing Deep analysis.")
        XCTAssertTrue(session.quickReader.reviewsCompleted.isEmpty, "Not counted as any review")
        let saved = MobileSession(storageDirectory: root)
        XCTAssertEqual(saved.deepThought, "Existing Deep analysis.", "The saved conversation is untouched")
        XCTAssertEqual(saved.quickSummary, "- Review on Thursday.")

        session.newConversation()
        XCTAssertNil(session.suggestedAsk.question, "A new conversation closes the ask")
    }

    func testAFailedAskKeepsTheChipAndSaysWhy() async {
        let stub = SuggestionStub(response: "", failure: URLError(.notConnectedToInternet))
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        session.notes = "Pricing is open."
        session.quickReader.offerSuggestions(["Draft a reminder"])
        XCTAssertTrue(session.askSuggested("Draft a reminder"))
        await session.suggestedAsk.waitForAnswer()
        XCTAssertNotNil(session.suggestedAsk.error)
        XCTAssertEqual(session.suggestedPrompts, ["Draft a reminder"], "Tap it again to retry")
    }

    /// Review finding: the chip used to be used up before a size limit refused the request. A long
    /// conversation is now answered from what fits, like every on-demand answer (#114).
    func testALongConversationIsAnsweredFromWhatFitsTheAppleWindow() async throws {
        let onDevice = SuggestionStub(response: "Draft: see you Thursday.")
        let session = MobileSession(storageDirectory: root)
        session.onDeviceProviderOverride = onDevice
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .apple
        session.notes = String(repeating: "Pricing is open. ", count: 600)
        session.quickReader.offerSuggestions(["Draft a reminder"])
        XCTAssertTrue(session.askSuggested("Draft a reminder"))
        await session.suggestedAsk.waitForAnswer()
        let request = try XCTUnwrap(onDevice.requests.last)
        let size = request.system.count + request.messages.reduce(0) { $0 + $1.content.count }
        XCTAssertLessThanOrEqual(size, PromptBudget.appleIntelligenceCharacters)
        XCTAssertTrue(request.messages.last?.content.hasSuffix(" Answer briefly.") ?? false)
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
        XCTAssertEqual(session.suggestedAsk.answer, "Draft: see you Thursday.")
    }

    func testABlockedTapSendsNothingAndKeepsTheChip() {
        let stub = SuggestionStub(response: "unused")
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        session.quickReader.offerSuggestions(["Draft a reminder"])
        XCTAssertNotNil(session.suggestionBlockReason, "Nothing to answer from yet")
        XCTAssertFalse(session.askSuggested("Draft a reminder"))
        XCTAssertEqual(session.suggestedPrompts, ["Draft a reminder"])
        XCTAssertNotNil(session.message)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    /// Review finding: a model change during a manual refresh used to let the old model's chips land.
    func testChipsFromARefreshStartedBeforeAProviderChangeAreDropped() async {
        let stub = SuggestionStub(response: #"{"action":"publish","context":"Pricing","bullets":["Pricing is open."],"#
            + #""reviews":[],"suggestions":["Old model chip"]}"#)
        let session = MobileSession(storageDirectory: root, summaryProvider: stub)
        stub.onStream = { MainActor.assumeIsolated { session.ai.quickSettingsChanged?() } }
        session.notes = "Pricing is still open."
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "- Pricing is open.")
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
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
}
