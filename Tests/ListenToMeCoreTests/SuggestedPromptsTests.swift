import XCTest
@testable import ListenToMeCore

/// Context-aware "Suggested" prompt chips (#61): validation, cadence, clearing, the evaluator and
/// prose contracts that carry them, and the macOS session's tap path. No real model is called.
final class SuggestedPromptsTests: XCTestCase {

    // MARK: - Validation

    func testSanitizeCleansMarkersAndQuotesAndKeepsAtMostThree() {
        XCTAssertEqual(SuggestedPrompts.sanitize([
            "- Counter the net-30 ask", "  \"Summarize pricing options\"  ", "1. Who owns the rollout?",
            "> Draft a reply to Sam", "Ask about the budget",
        ]), ["Counter the net-30 ask", "Summarize pricing options", "Who owns the rollout?"])
        XCTAssertEqual(SuggestedPrompts.clean("**Ask   about   Q3**"), "Ask about Q3", "Emphasis is decoration")
        XCTAssertEqual(SuggestedPrompts.clean("“Clarify   the   SLA”"), "Clarify the SLA")
    }

    func testSanitizeDedupesIgnoringCasePunctuationAndSpacing() {
        XCTAssertEqual(SuggestedPrompts.sanitize([
            "Ask about pricing?", "ask about  pricing", "ASK ABOUT PRICING!", "Ask about pricíng", "Next steps?",
        ]), ["Ask about pricing?", "Next steps?"])
    }

    func testLengthLimitRejectsRatherThanTruncates() {
        let sixty = String(repeating: "a", count: 59) + "?"
        XCTAssertEqual(SuggestedPrompts.clean(sixty), sixty)
        XCTAssertNil(SuggestedPrompts.clean(sixty + "b"), "A cut-off literal prompt is not a prompt")
    }

    func testJunkIsRejected() {
        let junk = [
            "", "   ", "-", "??", "Ok", "none", "N/A", "No suggestions yet", "request", "Suggested:",
            "{\"action\":\"keep\"}", "[\"a\"]", "<transcript>", "See https://example.com",
            "Visit www.example.com", "Line one\nLine two", "a | b | c", "```",
        ]
        for value in junk { XCTAssertNil(SuggestedPrompts.clean(value), value) }
        XCTAssertEqual(SuggestedPrompts.sanitize(junk), [])
        XCTAssertEqual(SuggestedPrompts.clean("问一下预算"), "问一下预算", "Non-Latin requests are kept")
    }

    // MARK: - Cadence and rate limiting

    func testFirstSetShowsAtOnceAndLaterSetsWaitOutTheRefreshWindow() {
        var chips = SuggestedPrompts()
        XCTAssertTrue(chips.offer(["Ask about pricing"], at: 100))
        XCTAssertFalse(chips.offer(["Who owns onboarding?"], at: 105), "Chips must not change under the pointer")
        XCTAssertEqual(chips.prompts, ["Ask about pricing"])
        // The held set appears on the first pass after the window, even one that brings nothing.
        XCTAssertFalse(chips.offer([], at: 110))
        XCTAssertTrue(chips.offer([], at: 100 + SuggestedPrompts.minimumRefreshInterval))
        XCTAssertEqual(chips.prompts, ["Who owns onboarding?"])
        XCTAssertFalse(chips.offer([], at: 500), "Nothing pending: an empty pass keeps what is showing")
        XCTAssertEqual(chips.prompts, ["Who owns onboarding?"])
    }

    func testNewestHeldSetWinsAndIdenticalSetsAreNoOps() {
        var chips = SuggestedPrompts()
        chips.offer(["One idea"], at: 0)
        chips.offer(["Second idea"], at: 5)
        chips.offer(["Third idea"], at: 10)
        XCTAssertTrue(chips.offer([], at: 25))
        XCTAssertEqual(chips.prompts, ["Third idea"])
        XCTAssertFalse(chips.offer(["Third idea"], at: 100), "An unchanged set does not restart the window")
    }

    func testAPassTheUserAskedForReplacesChipsAtOnce() {
        var chips = SuggestedPrompts()
        chips.offer(["Ask about pricing"], at: 100)
        XCTAssertTrue(chips.offer(["Draft a reply to Sam"], at: 101, force: true))
        XCTAssertEqual(chips.prompts, ["Draft a reply to Sam"])
    }

    // MARK: - Using and clearing

    func testATappedChipLeavesTheRowAndIsNotSuggestedAgain() {
        var chips = SuggestedPrompts()
        chips.offer(["Ask about pricing", "Next steps?"], at: 0)
        chips.use("Ask about pricing")
        XCTAssertEqual(chips.prompts, ["Next steps?"])
        chips.offer(["ask about pricing!", "Who decides?"], at: 100)
        XCTAssertEqual(chips.prompts, ["Who decides?"])
    }

    func testClearDropsChipsAndHeldSetsButRemembersUsedOnes() {
        var chips = SuggestedPrompts()
        chips.offer(["Ask about pricing"], at: 0)
        chips.use("Ask about pricing")
        chips.offer(["Next steps?"], at: 1)
        chips.offer(["Held for later"], at: 2)
        chips.clear()
        XCTAssertTrue(chips.isEmpty)
        XCTAssertFalse(chips.offer([], at: 1_000), "A held set must not resurface after clearing")
        chips.offer(["Ask about pricing", "Fresh idea"], at: 1_001)
        XCTAssertEqual(chips.prompts, ["Fresh idea"])
        XCTAssertTrue(SuggestedPrompts().isEmpty, "A new conversation starts with no chips and no memory")
    }

    // MARK: - Evaluator contract

    func testDecisionCarriesSanitizedSuggestionsAndOldEnvelopesStayValid() throws {
        let with = #"{"action":"publish","context":"Pricing","bullets":["Pricing is open."],"reviews":[],"#
            + #""suggestions":["Summarize pricing options","summarize pricing options","{junk}","none"]}"#
        let decision = try QuickSummaryDecision.parse(with)
        XCTAssertEqual(decision.summary, "- Pricing is open.")
        XCTAssertEqual(decision.suggestions, ["Summarize pricing options"])
        let without = try QuickSummaryDecision.parse(
            #"{"action":"keep","context":"x","bullets":[],"reviews":[]}"#)
        XCTAssertEqual(without.suggestions, [])
    }

    func testMalformedSuggestionsCostTheChipsNeverTheRecap() throws {
        for value in [#""Ask about pricing""#, "42", "null", #"[1, 2]"#] {
            let response = #"{"action":"publish","context":"x","bullets":["Recap"],"reviews":[],"suggestions":"#
                + value + "}"
            let decision = try QuickSummaryDecision.parse(response)
            XCTAssertEqual(decision.summary, "- Recap", value)
            XCTAssertEqual(decision.suggestions, [], value)
        }
        XCTAssertThrowsError(try QuickSummaryDecision.parse(
            #"{"action":"publish","context":"x","bullets":["a"],"reviews":[],"suggestions":[],"extra":1}"#),
            "Only the documented optional key is accepted")
    }

    func testEvaluatorPromptAsksForBoundedSuggestionsOnlyWithPublish() {
        let prompt = QuickSummaryContext.instructions
        XCTAssertTrue(prompt.contains(#""suggestions":["request"]"#))
        XCTAssertTrue(prompt.contains("<=60 characters"))
        XCTAssertTrue(prompt.contains("suggestions=[] with keep"))
        XCTAssertTrue(QuickSummaryContext.instructions(responseLanguage: "French").contains("suggestions"),
                      "The response-language variant keeps the suggestion contract")
        let schema = QuickSummaryDecision.jsonSchema
        XCTAssertTrue((schema["required"] as? [String] ?? []).contains("suggestions"))
    }

    // MARK: - On-device prose

    func testProseSuggestionsAreReadStrictlyAndNeverShownAsTakeaways() {
        let response = """
        - Pricing is still open.
        - Sam owns the proposal.
        **Suggested:**
        > Summarize pricing options
        > Draft a reply to Sam
        > {"oops": true}
        Thanks for listening!
        > Ignored after the block ended
        """
        let split = SuggestedPrompts.splitProse(response)
        XCTAssertEqual(split.suggestions, ["Summarize pricing options", "Draft a reply to Sam"])
        XCTAssertEqual(QuickSummaryContext.proseSummary(response), "- Pricing is still open.\n- Sam owns the proposal.")
    }

    func testProseWithoutTheHeadingHasNoChipsAndAnUnchangedRecap() {
        let response = "- Pricing is still open.\n> Summarize pricing options"
        XCTAssertEqual(SuggestedPrompts.splitProse(response).suggestions, [])
        XCTAssertEqual(SuggestedPrompts.splitProse(response).body, response)
        XCTAssertEqual(QuickSummaryContext.proseSummary(response), "- Pricing is still open.")
        XCTAssertEqual(SuggestedPrompts.splitProse("No key takeaway yet.").suggestions, [])
        XCTAssertNil(QuickSummaryContext.proseSummary("No key takeaway yet.\nSuggested:\n> Ask something"))
        XCTAssertTrue(QuickSummaryContext.manualProseInstructions.contains(SuggestedPrompts.proseInstructions))
        XCTAssertFalse(QuickSummaryContext.manualProseInstructions.contains("JSON"))
    }

    // MARK: - Tapped prompt

    func testATappedChipIsSentLiterallyOnOneLineThroughQuickAndDeep() {
        let context = PromptContext(messages: [TranscriptSegment(source: .others, text: "Net 30?", isFinal: true,
                                                                 start: 0, end: 1)], notes: nil)
        let quick = PromptBuilder.build(context: context, action: .ask("Counter the net-30 ask"))
        let user = quick.messages.last?.content ?? ""
        XCTAssertTrue(user.hasSuffix(#"The user asks: "Counter the net-30 ask". Respond to that request, "#
            + "grounded in the transcript and notes. Answer briefly."))
        XCTAssertTrue(user.contains("<transcript>"), "The tapped request is answered from the fenced transcript")
        let deep = PromptBuilder.buildDeep(context: context, action: .ask("Line one\nLine two"))
        XCTAssertTrue(deep.messages.last?.content.contains(#""Line one Line two""#) ?? false)
        XCTAssertNotEqual(quick.system, deep.system)
    }
}

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
        session.quickReader.offerSuggestions(["Summarize pricing options"])
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
