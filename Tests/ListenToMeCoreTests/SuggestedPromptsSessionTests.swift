import XCTest
@testable import ListenToMeCore

// MARK: - Reader and session

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1_000
    var now: TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

/// Answers the Quick evaluator with a decision carrying `suggestions`, and every other request with
/// a fixed answer, recording what it was asked.
private final class SuggestingProvider: LLMProvider, @unchecked Sendable {
    let id = "suggesting"
    private let lock = NSLock()
    private var _requests: [LLMRequest] = []
    private var _suggestions: [String]
    var requests: [LLMRequest] { lock.withLock { _requests } }
    init(suggestions: [String]) { _suggestions = suggestions }
    func suggest(_ values: [String]) { lock.withLock { _suggestions = values } }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let suggestions = lock.withLock { _requests.append(request); return _suggestions }
        return AsyncThrowingStream { continuation in
            if request.purpose == .quickEvaluation {
                let object: [String: Any] = ["action": "publish", "context": "Pricing", "bullets": ["Pricing is open."],
                                             "reviews": [], "suggestions": suggestions]
                let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
                continuation.yield(String(bytes: data, encoding: .utf8) ?? "")
            } else {
                continuation.yield("Here is the answer.")
            }
            continuation.finish()
        }
    }
}

@MainActor
final class SuggestedPromptsReaderTests: XCTestCase {
    private func batch(_ text: String, _ context: QuickSummaryContext = QuickSummaryContext()) throws
        -> QuickSummaryContext.Batch {
        try XCTUnwrap(context.batch([.init(id: "a", text: text)], summary: ""))
    }

    func testACompletedReadRefreshesChipsOnTheReadersClock() async throws {
        let clock = Clock()
        let reader = QuickSummaryReader(now: { clock.now })
        let provider = SuggestingProvider(suggestions: ["Summarize pricing options", "none"])
        await reader.read(try batch("Pricing?"), provider: provider, isCurrent: { true }, apply: { _ in })
        XCTAssertEqual(reader.suggestions.prompts, ["Summarize pricing options"])

        provider.suggest(["Who owns pricing?"])
        await reader.read(try batch("Pricing, Sam?", reader.context), provider: provider,
                          isCurrent: { true }, apply: { _ in })
        XCTAssertEqual(reader.suggestions.prompts, ["Summarize pricing options"], "Held inside the refresh window")
        clock.advance(SuggestedPrompts.minimumRefreshInterval)
        provider.suggest([])
        await reader.read(try batch("Pricing, Sam, Friday?", reader.context), provider: provider,
                          isCurrent: { true }, apply: { _ in })
        XCTAssertEqual(reader.suggestions.prompts, ["Who owns pricing?"])
    }

    func testStaleOrCancelledReadsAndPartialCatchUpNeverProduceChips() async throws {
        let reader = QuickSummaryReader()
        let provider = SuggestingProvider(suggestions: ["Summarize pricing options"])
        await reader.read(try batch("Pricing?"), provider: provider, isCurrent: { false }, apply: { _ in })
        XCTAssertTrue(reader.suggestions.isEmpty, "A read invalidated by newer speech is discarded")

        let pieces = (0..<12).map { QuickSummaryContext.Piece(id: "p\($0)", text: "Point \($0)") }
        let partial = try XCTUnwrap(QuickSummaryContext().batch(pieces, summary: ""))
        XCTAssertTrue(partial.hasMore)
        await reader.read(partial, provider: provider, isCurrent: { true }, apply: { _ in })
        XCTAssertTrue(reader.suggestions.isEmpty, "A catch-up read has not seen the whole conversation yet")
    }

    /// Review finding: a manual refresh is not cancelled by a settings change, so its chips must not
    /// come back after the provider or model changed.
    func testChipsFromAPassThatStartedBeforeAProviderChangeAreDropped() async throws {
        let reader = QuickSummaryReader()
        reader.startManualQuick()
        reader.providerChanged()
        reader.offerSuggestions(["Old model chip"])
        XCTAssertTrue(reader.suggestions.isEmpty)
        reader.startManualQuick()
        reader.offerSuggestions(["New model chip"])
        XCTAssertEqual(reader.suggestions.prompts, ["New model chip"])

        let auto = QuickSummaryReader()
        let provider = SuggestingProvider(suggestions: ["Old model chip"])
        await auto.read(try batch("Pricing?"), provider: provider,
                        isCurrent: { auto.clearSuggestions(); return true }, apply: { _ in })
        XCTAssertTrue(auto.suggestions.isEmpty, "Chips cleared while the read ran never come back")
        XCTAssertEqual(auto.completedReads, 1, "The recap itself still lands")
    }

    func testResetProviderChangeAndManualPassesManageChips() {
        let reader = QuickSummaryReader()
        reader.offerSuggestions(["Ask about pricing"])
        XCTAssertEqual(reader.suggestions.prompts, ["Ask about pricing"])
        reader.offerSuggestions(["Draft a reply to Sam"])
        XCTAssertEqual(reader.suggestions.prompts, ["Draft a reply to Sam"], "A manual pass replaces at once")
        reader.useSuggestion("Draft a reply to Sam")
        XCTAssertTrue(reader.suggestions.isEmpty)
        reader.offerSuggestions(["Next steps?"])
        reader.providerChanged()
        XCTAssertTrue(reader.suggestions.isEmpty)
        reader.offerSuggestions(["Next steps?"])
        reader.reset()
        XCTAssertTrue(reader.suggestions.isEmpty)
    }

    // MARK: MeetingSession (macOS)

    private func makeSession(_ provider: SuggestingProvider) -> MeetingSession {
        MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 8),
                       makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                       makeProvider: { model -> any LLMProvider in
                           model == "L" ? MockLLMProvider(id: model, deltas: ["[L]"]) : provider
                       }, models: [.listener: "L", .quick: "Q", .deep: "D"],
                       autoInterval: .milliseconds(10))
    }

    private func waitForChips(_ session: MeetingSession) async throws {
        for _ in 0..<400 where session.suggestedPrompts.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    }

    func testAutoProducesChipsAndATapSendsTheLiteralPromptOnce() async throws {
        let provider = SuggestingProvider(suggestions: ["Counter the net-30 ask", "Summarize pricing options"])
        let session = makeSession(provider)
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(TranscriptSegment(source: .you, text: "We propose net-30 pricing.", isFinal: true,
                                               start: 0, end: 1))
        try await waitForChips(session)
        XCTAssertEqual(session.suggestedPrompts, ["Counter the net-30 ask", "Summarize pricing options"])
        let evaluations = provider.requests.count
        XCTAssertTrue(provider.requests.allSatisfy { $0.purpose == .quickEvaluation },
                      "Chips ride on the evaluator: no request exists only to make them")

        await session.askSuggested("Counter the net-30 ask")
        XCTAssertEqual(provider.requests.count, evaluations + 1, "A tap is exactly one request")
        let sent = try XCTUnwrap(provider.requests.last)
        XCTAssertEqual(sent.purpose, .chat)
        XCTAssertTrue(sent.messages.last?.content.contains(#"The user asks: "Counter the net-30 ask""#) ?? false)
        XCTAssertEqual(session.quickSuggestion, "Here is the answer.")
        XCTAssertEqual(session.suggestedPrompts, ["Summarize pricing options"])

        await session.askSuggested("Summarize pricing options", deep: true)
        XCTAssertEqual(session.deepAnswer, "Here is the answer.")
        XCTAssertEqual(provider.requests.count, evaluations + 2)
        session.stop()
    }

    func testAutoOffProducesNoChipsAndMakesNoCall() async throws {
        let provider = SuggestingProvider(suggestions: ["Summarize pricing options"])
        let session = makeSession(provider)
        try await session.start()
        await session.ingest(TranscriptSegment(source: .you, text: "We propose net-30 pricing.", isFinal: true,
                                               start: 0, end: 1))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
        XCTAssertFalse(provider.requests.contains { $0.purpose == .quickEvaluation })
        session.stop()
    }

    func testAIOffProviderChangeAndNewConversationClearChips() async throws {
        let provider = SuggestingProvider(suggestions: ["Summarize pricing options"])
        let session = makeSession(provider)
        session.autoSummaryEnabled = true
        session.quickReader.offerSuggestions(["Summarize pricing options"])
        XCTAssertEqual(session.suggestedPrompts, ["Summarize pricing options"])
        session.aiEnabled = false
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
        let before = provider.requests.count
        await session.askSuggested("Summarize pricing options")
        XCTAssertEqual(provider.requests.count, before, "Nothing is sent while AI is off")
        session.aiEnabled = true
        XCTAssertTrue(session.suggestedPrompts.isEmpty, "Turning AI off cleared the chips")

        session.quickReader.offerSuggestions(["Next steps?"])
        session.setModel(.quick, "Other")
        XCTAssertTrue(session.suggestedPrompts.isEmpty)

        session.quickReader.offerSuggestions(["Next steps?"])
        session.resetConversation()
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
    }

    /// Review finding: on macOS only Auto makes chips, so turning it off must not leave them behind.
    func testTurningAutoOffClearsAndHidesChips() async throws {
        let provider = SuggestingProvider(suggestions: ["Summarize pricing options"])
        let session = makeSession(provider)
        session.autoSummaryEnabled = true
        session.quickReader.offerSuggestions(["Summarize pricing options"])
        XCTAssertEqual(session.suggestedPrompts, ["Summarize pricing options"])
        session.autoSummaryEnabled = false
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
        XCTAssertTrue(session.quickReader.suggestions.isEmpty, "Cleared, not merely hidden")
        session.autoSummaryEnabled = true
        XCTAssertTrue(session.suggestedPrompts.isEmpty)
    }

    func testStopKeepsChipsBecauseTheConversationIsStillAskable() async throws {
        let provider = SuggestingProvider(suggestions: ["Summarize pricing options"])
        let session = makeSession(provider)
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(TranscriptSegment(source: .you, text: "We propose net-30 pricing.", isFinal: true,
                                               start: 0, end: 1))
        try await waitForChips(session)
        await session.stopAndWait()
        XCTAssertEqual(session.suggestedPrompts, ["Summarize pricing options"])
    }
}
