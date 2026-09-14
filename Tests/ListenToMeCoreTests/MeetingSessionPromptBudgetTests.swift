import XCTest
@testable import ListenToMeCore

/// Issue #119: MeetingSession must clamp every prompt it builds to the role provider's context
/// window, and say so when it had to drop material. Providers without a window are unaffected.
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

    private func promptCharacters(_ request: LLMRequest?) -> Int {
        guard let request else { return 0 }
        return request.system.count + request.messages.reduce(0) { $0 + $1.content.count }
    }

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

    func testTruncationIsReportedToTheUser() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        XCTAssertNil(session.promptTruncationNotice)
        fill(store, characters: 60_000)
        await session.respondDeep(.recap)
        let notice = session.promptTruncationNotice
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.lowercased().contains("context") == true, notice ?? "")
    }

    func testShortMeetingOnALimitedProviderReportsNoTruncation() async {
        let (session, store, _) = makeSession(limit: PromptBudget.appleIntelligenceCharacters)
        store.apply(TranscriptSegment(source: .others, text: "Short meeting.", isFinal: true,
                                      start: 0, end: 1))
        await session.respondDeep(.recap)
        XCTAssertNil(session.promptTruncationNotice)
    }

    func testUnlimitedProviderKeepsTheFullTranscriptAndReportsNoTruncation() async {
        let (session, store, provider) = makeSession(limit: nil)
        fill(store, characters: 40_000)
        session.referenceContext = String(repeating: "R", count: 16_000)
        await session.respondDeep(.recap)
        XCTAssertGreaterThan(promptCharacters(provider.lastRequest), 40_000)
        XCTAssertNil(session.promptTruncationNotice)
    }
}
