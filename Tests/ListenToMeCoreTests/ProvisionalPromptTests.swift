import XCTest
@testable import ListenToMeCore

/// Issue #113: manual Quick/Deep/Listener prompts must include the speech the recognizer has not
/// finalized yet. SpeechAnalyzer can keep a hypothesis volatile for an entire recording, so a
/// finals-only prompt can answer a question that is minutes old — or claim none was asked.
@MainActor
final class ProvisionalPromptTests: XCTestCase {

    private func makeSession(limit: Int? = nil) -> (MeetingSession, ConversationStore, RecordingProvider) {
        let store = ConversationStore()
        let provider = RecordingProvider(deltas: ["ok"], maxPromptCharacters: limit)
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: 0,
            clock: { 0 }
        )
        return (session, store, provider)
    }

    private func partial(_ text: String, _ source: SpeakerSource = .others,
                         id: UUID = UUID()) -> TranscriptSegment {
        TranscriptSegment(id: id, source: source, text: text, isFinal: false, start: 0, end: 1)
    }

    private func final(_ text: String, _ source: SpeakerSource = .others,
                       id: UUID = UUID()) -> TranscriptSegment {
        TranscriptSegment(id: id, source: source, text: text, isFinal: true, start: 0, end: 1)
    }

    private let question = "So what would you actually do about the migration deadline?"

    // MARK: - Store

    func testProvisionalContextTagsAndFiltersShortHypotheses() {
        let store = ConversationStore()
        store.apply(partial("too short", .you))
        XCTAssertTrue(store.provisionalContext(maxChars: 4_000).isEmpty,
                      "A hypothesis under the shared 24-character threshold is noise, not context.")
        store.apply(partial(question, .others))
        let context = store.provisionalContext(maxChars: 4_000)
        XCTAssertEqual(context.count, 1)
        XCTAssertTrue(context[0].text.contains(question))
        XCTAssertTrue(context[0].text.contains("(provisional)"))
        XCTAssertFalse(context[0].isFinal, "Provisional lines must stay non-final for the ledgers.")
    }

    func testProvisionalContextRespectsItsBudget() {
        let store = ConversationStore()
        store.apply(partial(String(repeating: "a", count: 5_000), .others))
        let context = store.provisionalContext(maxChars: 300)
        let cost = context.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) }
        XCTAssertLessThanOrEqual(cost, 300)
        XCTAssertFalse(context.isEmpty)
        XCTAssertTrue(store.provisionalContext(maxChars: 10).isEmpty,
                      "A budget too small for any meaningful speech yields nothing at all.")
    }

    // MARK: - Manual panes

    func testQuickPromptIncludesPendingPartial() async {
        let (session, store, provider) = makeSession()
        store.apply(final("Earlier we agreed on the schema.", .you))
        store.apply(partial(question))
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains(question), "Quick answered without the question that was just asked.")
        XCTAssertTrue(user.contains("(provisional)"))
        XCTAssertTrue(user.contains("Earlier we agreed on the schema."))
    }

    func testDeepPromptIncludesPendingPartial() async {
        let (session, store, provider) = makeSession()
        store.apply(partial(question))
        await session.respondDeep(.answerQuestion)
        XCTAssertTrue((provider.lastUser ?? "").contains(question))
    }

    func testListenerSendsProvisionalOnlyOnceTheLedgerHasCaughtUp() async {
        let (session, store, provider) = makeSession()
        let id = UUID()
        store.apply(final("Opening remarks.", .you))
        store.apply(partial(question, .others, id: id))
        // Unsummarized speech is still queued, so this batch must carry evidence only: the listener
        // record is cumulative, and re-sending the same unconfirmed wording per chained batch is how
        // a hypothesis ends up duplicated in a saved summary.
        await session.refreshListener()
        XCTAssertTrue((provider.lastUser ?? "").contains("Opening remarks."))
        XCTAssertFalse((provider.lastUser ?? "").contains("(provisional)"),
                       "A chained Listener batch must not re-send provisional speech.")

        // Ledger caught up: now the volatile hypothesis is the only new evidence there is.
        await session.refreshListener()
        XCTAssertTrue((provider.lastUser ?? "").contains(question))
        XCTAssertTrue((provider.lastUser ?? "").contains(PromptBuilder.provisionalNotice),
                      "The prompt must define what the (provisional) tag means.")

        // The hypothesis was not summarized: once it finalizes it must still reach the listener.
        store.apply(final(question, .others, id: id))
        await session.refreshListener()
        XCTAssertTrue((provider.lastUser ?? "").contains(question),
                      "A provisional line must never advance the summarized ledger.")
    }

    func testProvisionalNoticeAccompaniesTaggedLinesOnly() async {
        let (session, store, provider) = makeSession()
        store.apply(final("A finalized line only.", .you))
        await session.respondQuick(.answerQuestion)
        XCTAssertFalse((provider.lastUser ?? "").contains(PromptBuilder.provisionalNotice))
        store.apply(partial(question))
        await session.respondQuick(.answerQuestion)
        XCTAssertTrue((provider.lastUser ?? "").contains(PromptBuilder.provisionalNotice))
    }

    /// `recentContext` and the listener batch always keep at least one segment, however large, so a
    /// provisional allowance read from the nominal budget alone could push the assembled prompt past
    /// a provider's cap.
    func testOneOversizedFinalLeavesNoRoomForProvisionalText() {
        let store = ConversationStore()
        store.apply(final(String(repeating: "f", count: 3_000), .you))
        store.apply(partial(String(repeating: "p", count: 2_000), .others))
        let engine = ContextEngine(debounce: 5)
        let context = engine.buildContext(from: store, notes: nil, maxChars: 4_000)
        let cost = context.messages.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) }
        XCTAssertLessThanOrEqual(cost, 4_000, "The oversized final must not push the prompt past the cap.")
        // What is left after that one line is small, so the hypothesis is trimmed to fit, not dropped.
        XCTAssertTrue(context.messages.contains { !$0.isFinal })
        XCTAssertLessThan(context.messages.filter { !$0.isFinal }[0].text.count, 2_000)

        // And when the finalized line alone fills the whole budget, nothing provisional fits at all.
        let tight = ConversationStore()
        tight.apply(final(String(repeating: "f", count: 3_990), .you))
        tight.apply(partial(String(repeating: "p", count: 2_000), .others))
        let tightContext = engine.buildContext(from: tight, notes: nil, maxChars: 4_000)
        XCTAssertLessThanOrEqual(tightContext.messages.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) },
                                 4_000)
        XCTAssertTrue(tightContext.messages.allSatisfy(\.isFinal))
    }

    /// The failure scenario from the issue: a recognizer that never finalizes anything at all.
    func testSessionThatNeverFinalizesStillProducesGroundedPrompts() async {
        let (session, store, provider) = makeSession()
        store.apply(partial("Everything in this meeting stayed a volatile hypothesis.", .others))
        await session.respondQuick(.answerQuestion)
        XCTAssertTrue((provider.lastUser ?? "").contains("volatile hypothesis"))
        await session.refreshListener()
        XCTAssertTrue((provider.lastUser ?? "").contains("volatile hypothesis"))
    }

    func testProvisionalTextStillFitsAnAppleSizedWindow() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        for index in 0..<200 {
            store.apply(final("Finalized line number \(index) with some substance to it.", .you))
        }
        store.apply(partial(String(repeating: "unfinalized speech ", count: 900), .others))
        await session.respondQuick(.answerQuestion)
        let request = provider.lastRequest
        let characters = (request?.system.count ?? 0)
            + (request?.messages.reduce(0) { $0 + $1.content.count } ?? 0)
        XCTAssertLessThanOrEqual(characters, limit)
        XCTAssertTrue((provider.lastUser ?? "").contains("unfinalized speech"))

        await session.refreshListener()
        let listener = provider.lastRequest
        let listenerCharacters = (listener?.system.count ?? 0)
            + (listener?.messages.reduce(0) { $0 + $1.content.count } ?? 0)
        XCTAssertLessThanOrEqual(listenerCharacters, limit)
    }
}
