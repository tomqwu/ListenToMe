import XCTest
@testable import ListenToMeCore

/// Issue #119: MeetingSession must bound the *assembled* prompt — system prompt, directives,
/// speaker labels, summary, notes, references and transcript — to the role provider's context
/// window, and say what it dropped. Providers without a window are unaffected.
@MainActor
final class MeetingSessionPromptBudgetTests: XCTestCase {

    private func makeSession(limit: Int?) -> (MeetingSession, ConversationStore, RecordingProvider) {
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

    /// Long lines: a few big segments.
    private func fill(_ store: ConversationStore, characters: Int) {
        var written = 0
        var index = 0
        while written < characters {
            let text = String(repeating: "word ", count: 40) + "#\(index)"
            store.apply(TranscriptSegment(source: .others, text: text, isFinal: true,
                                          start: Double(index), end: Double(index) + 1))
            written += text.count
            index += 1
        }
    }

    /// Short lines: the label overhead case — hundreds of 20-60 character utterances, each carrying
    /// a named speaker label that the prompt pays for but raw `text.count` budgeting ignores.
    private func fillShortLabeledUtterances(_ store: ConversationStore, count: Int) {
        for index in 0..<count {
            var segment = TranscriptSegment(source: index.isMultiple(of: 2) ? .you : .others,
                                            text: "Right, and then we should check item \(index).",
                                            isFinal: true, start: Double(index), end: Double(index) + 1)
            segment.speakerName = index.isMultiple(of: 2) ? "Alexandra Petrova" : "Bartholomew Chen"
            store.apply(segment)
        }
    }

    private func promptCharacters(_ request: LLMRequest?) -> Int {
        guard let request else { return 0 }
        return request.system.count + request.messages.reduce(0) { $0 + $1.content.count }
    }

    // MARK: - The assembled prompt fits

    func testAppleSizedProviderNeverReceivesAnOversizedDeepRecapPrompt() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fill(store, characters: 60_000)
        session.referenceContext = String(repeating: "R", count: 16_000)
        await session.respondDeep(.recap)
        XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit)
    }

    func testAppleSizedProviderNeverReceivesAnOversizedQuickPrompt() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fill(store, characters: 30_000)
        session.referenceContext = String(repeating: "R", count: 16_000)
        await session.respondQuick(.answerQuestion)
        XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit)
    }

    func testAppleSizedProviderNeverReceivesAnOversizedListenerPrompt() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fill(store, characters: 60_000)
        await session.refreshListener()
        XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit)
    }

    /// Speaker labels are prompt characters too: 800 short, named utterances add ~15k of labels
    /// alone, which a `text.count`-only budget would not charge for.
    func testManyShortLabeledUtterancesStillFitTheWindow() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fillShortLabeledUtterances(store, count: 800)
        for action in [ResponseAction.recap, .answerQuestion, .actionItems] {
            await session.respondDeep(action)
            XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit,
                                     "deep \(action)")
            await session.respondQuick(action)
            XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit,
                                     "quick \(action)")
        }
        await session.refreshListener()
        XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit, "listener")
    }

    /// Notes, the rolling summary, persona and language directives all live inside the same window.
    func testOversizedNotesAndDirectivesStillFitTheWindow() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fillShortLabeledUtterances(store, count: 300)
        session.notes = String(repeating: "note ", count: 4_000)
        session.responseLanguage = "Simplified Chinese"
        session.personaGuidance = String(repeating: "persona ", count: 20)
        session.referenceContext = String(repeating: "R", count: 16_000)
        // Give the session a completed listener summary to carry into Quick/Deep.
        await session.refreshListener()
        XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit, "listener")
        await session.respondDeep(.recap)
        XCTAssertLessThanOrEqual(promptCharacters(provider.lastRequest), limit, "deep")
    }

    // MARK: - Notice

    func testTruncationIsReportedToTheUser() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        XCTAssertNil(session.promptTruncationNotice)
        fill(store, characters: 60_000)
        await session.respondDeep(.recap)
        let notice = session.promptTruncationNotice
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.lowercased().contains("context window") == true, notice ?? "")
    }

    /// A partial listener batch is not loss — the ledger summarizes the rest on the next pass — but
    /// notes that had to be cut out of the listener prompt are.
    func testListenerReportsClampedNotesButNotOrdinaryBatching() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        fill(store, characters: 60_000)
        await session.refreshListener()
        XCTAssertNil(session.promptTruncationNotice)

        let (other, otherStore, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        otherStore.apply(TranscriptSegment(source: .others, text: "Short.", isFinal: true,
                                           start: 0, end: 1))
        other.notes = String(repeating: "note ", count: 4_000)
        await other.refreshListener()
        XCTAssertNotNil(other.promptTruncationNotice)
    }

    func testNoticeNamesReferencesWhenOnlyReferencesWereDropped() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        store.apply(TranscriptSegment(source: .others, text: "Short meeting.", isFinal: true,
                                      start: 0, end: 1))
        session.referenceContext = String(repeating: "R", count: 16_000)
        await session.respondDeep(.recap)
        let notice = session.promptTruncationNotice
        XCTAssertTrue(notice?.contains("reference") == true, notice ?? "")
        XCTAssertFalse(notice?.contains("most recent speech") == true, notice ?? "")
    }

    func testShortMeetingOnALimitedProviderReportsNoTruncation() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        store.apply(TranscriptSegment(source: .others, text: "Short meeting.", isFinal: true,
                                      start: 0, end: 1))
        await session.respondDeep(.recap)
        XCTAssertNil(session.promptTruncationNotice)
    }

    /// The smoke test asserts the notice disappears when the user switches provider.
    func testChangingModelClearsTheNotice() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        fill(store, characters: 60_000)
        await session.respondDeep(.recap)
        XCTAssertNotNil(session.promptTruncationNotice)
        session.setModel(.deep, "another-model")
        XCTAssertNil(session.promptTruncationNotice)
    }

    // MARK: - Unlimited providers are untouched

    func testUnlimitedProviderKeepsTheFullTranscriptAndReportsNoTruncation() async {
        let (session, store, provider) = makeSession(limit: nil)
        fill(store, characters: 40_000)
        session.referenceContext = String(repeating: "R", count: 16_000)
        await session.respondDeep(.recap)
        XCTAssertGreaterThan(promptCharacters(provider.lastRequest), 40_000)
        XCTAssertNil(session.promptTruncationNotice)
    }

    func testUnlimitedProviderKeepsFullNotesAndSummary() async {
        let (session, store, provider) = makeSession(limit: nil)
        fill(store, characters: 5_000)
        session.notes = String(repeating: "note ", count: 4_000)
        await session.respondQuick(.answerQuestion)
        let user = provider.lastRequest?.messages.last?.content ?? ""
        XCTAssertTrue(user.contains(session.notes.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertNil(session.promptTruncationNotice)
    }
}
