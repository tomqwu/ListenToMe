import XCTest
@testable import ListenToMeCore

/// The domain's summary headings shape summaries only: the macOS Listener and automatic Summary
/// reviews, never Quick or Deep (#222 review).
@MainActor
final class VocabularySummaryLayoutTests: XCTestCase {
    private let headings = "Summary headings: History, Findings, Plan."

    func testOnlyTheSummaryReviewCarriesTheHeadings() {
        let directives = AutomaticReviewDirectives(personaGuidance: "Domain: Medical.", summaryGuidance: headings)
        XCTAssertTrue(directives.system(for: .summary).contains("Domain: Medical. " + headings))
        XCTAssertTrue(directives.system(for: .deep).contains("Domain: Medical."))
        XCTAssertFalse(directives.system(for: .deep).contains("headings"))
    }

    func testTheListenerGetsTheHeadingsButQuickAndDeepDoNot() async {
        let provider = RecordingProvider(deltas: ["ok"])
        let store = ConversationStore()
        let session = MeetingSession(store: store, context: ContextEngine(debounce: 5),
                                     makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                                     makeProvider: { _ in provider },
                                     models: [.listener: "L", .quick: "Q", .deep: "D"], clock: { 0 })
        session.personaGuidance = "Domain: Medical."
        session.summaryGuidance = headings
        store.apply(TranscriptSegment(source: .others, text: "Troponin was flat.", isFinal: true, start: 0, end: 1))
        await session.refreshListener()
        XCTAssertTrue(provider.lastRequest?.system.contains("Domain: Medical. " + headings) == true)
        await session.respondQuick(.answerQuestion)
        XCTAssertTrue(provider.lastRequest?.system.contains("Domain: Medical.") == true)
        XCTAssertFalse(provider.lastRequest?.system.contains("headings") == true)
        await session.respondDeep(.recap)
        XCTAssertFalse(provider.lastRequest?.system.contains("headings") == true)
        XCTAssertEqual(session.listenerPersona, "Domain: Medical. " + headings)
    }
}
