import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Records the request and streams fixed events, optionally ending at the output limit.
private final class EventProvider: LLMProvider, @unchecked Sendable {
    let id = "event-test"
    var events: [LLMStreamEvent]
    private(set) var request: LLMRequest?
    init(_ events: [LLMStreamEvent]) { self.events = events }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: URLError(.badURL)) }
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        self.request = request
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Issues #114 and #215 on iOS: Quick and Deep answer a long conversation from what fits instead of
/// refusing it, the panel says which part was read, and an answer cut off at the model's output limit
/// keeps its text with a one-line notice.
@MainActor
final class MobileAnswerNoticeTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// One ~200-character line per minute.
    private func longConversation(minutes: Int) -> [TranscriptSegment] {
        (0..<minutes).map { minute in
            TranscriptSegment(source: .you, text: (minute == 1 ? "Pricing: we agreed on forty dollars per seat. " : "")
                              + "Minute \(minute): " + String(repeating: "talk ", count: 38), isFinal: true,
                              start: Double(minute * 60), end: Double(minute * 60 + 59))
        }
    }

    private func appleSession(_ provider: EventProvider) -> MobileSession {
        let session = MobileSession(storageDirectory: root)
        session.onDeviceProviderOverride = provider
        let original = session.ai.provider
        addTeardownBlock { @MainActor in session.ai.provider = original }
        session.ai.provider = .apple
        return session
    }

    /// A 45-minute conversation used to be refused on Apple Intelligence ("exceeds the selected
    /// provider's summary limit"). Deep now answers from the opening and the latest speech.
    func testAppleDeepAnswersALongConversationFromAnExcerptAndSaysSo() async throws {
        let provider = EventProvider([.content("Deep answer.")])
        let session = appleSession(provider)
        session.segments = longConversation(minutes: 45)
        await session.summarize(mode: .deep)
        XCTAssertNil(session.message, session.message ?? "")
        XCTAssertEqual(session.deepThought, "Deep answer.")
        let request = try XCTUnwrap(provider.request)
        XCTAssertLessThanOrEqual(request.system.count + (request.messages.first?.content.count ?? 0),
                                 PromptBudget.appleIntelligenceCharacters - PromptBudget.answerReserve,
                                 "The on-device window still holds")
        let user = request.messages.first?.content ?? ""
        XCTAssertTrue(user.contains("Pricing: we agreed"), "The opening is kept without a Summary")
        XCTAssertTrue(user.contains("Minute 44:"), "The latest speech is kept")
        XCTAssertTrue(user.contains("The transcript is an excerpt"))
        let lines = session.answerNotices.lines(for: .deep)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.first?.hasPrefix("Using the opening ~") == true, lines.description)
        // The Summary mode still refuses rather than summarizing part of the conversation.
        await session.summarize(mode: .summary)
        XCTAssertTrue(session.message?.contains("summary limit") == true, session.message ?? "")
    }

    func testAnExistingSummaryIsReusedForQuick() async throws {
        let provider = EventProvider([.content("- Pricing is $40 per seat.")])
        let session = appleSession(provider)
        session.segments = longConversation(minutes: 45)
        session.summary = "Earlier: pricing agreed at $40 per seat."
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "- Pricing is $40 per seat.")
        let user = try XCTUnwrap(provider.request?.messages.first?.content)
        XCTAssertTrue(user.contains("Earlier: pricing agreed at $40 per seat."))
        XCTAssertTrue(session.answerNotices.lines(for: .quick).first?
            .hasPrefix("Using your Summary and the last ~") == true)
    }

    func testAShortConversationHasNoNotice() async {
        let provider = EventProvider([.content("Deep answer.")])
        let session = appleSession(provider)
        session.segments = longConversation(minutes: 2)
        await session.summarize(mode: .deep)
        XCTAssertEqual(provider.request?.messages.first?.content, PromptData.block("transcript", session.summarySource))
        XCTAssertTrue(session.answerNotices.lines(for: .deep).isEmpty)
    }

    /// A cloud Deep answer that stopped at the limit keeps its text and says so; the next complete one
    /// clears the line.
    func testACutOffAnswerKeepsItsTextAndShowsTheNotice() async {
        let provider = EventProvider([.content("The first half of"), .outputLimitReached])
        let session = MobileSession(storageDirectory: root, summaryProvider: provider)
        session.notes = "Should we ship on Friday?"
        await session.summarize(mode: .deep)
        XCTAssertNil(session.message, session.message ?? "")
        XCTAssertEqual(session.deepThought, "The first half of")
        XCTAssertEqual(session.answerNotices.lines(for: .deep), [LLMOutputLimit.notice])
        XCTAssertTrue(session.answerNotices.lines(for: .summary).isEmpty)

        provider.events = [.content("Whole answer.")]
        await session.summarize(mode: .deep)
        XCTAssertEqual(session.deepThought, "Whole answer.")
        XCTAssertTrue(session.answerNotices.lines(for: .deep).isEmpty)
        // A new conversation starts without notes from the previous one.
        provider.events = [.content("Half"), .outputLimitReached]
        await session.summarize(mode: .summary)
        XCTAssertEqual(session.answerNotices.lines(for: .summary), [LLMOutputLimit.notice])
        session.newConversation()
        XCTAssertTrue(session.answerNotices.lines(for: .summary).isEmpty)
    }

    /// The cloud Quick evaluator answers in JSON; JSON cut off mid-object is unreadable, so the panel
    /// reports the output limit instead of a parser error, and keeps the previous takeaway.
    func testACutOffQuickEvaluationIsReportedAsTheOutputLimit() async {
        let provider = EventProvider([.content(#"{"action":"publish","bullets":["Pri"#), .outputLimitReached])
        let session = MobileSession(storageDirectory: root, summaryProvider: provider)
        session.notes = "Pricing is forty dollars per seat."
        session.quickSummary = "- Previous takeaway"
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "- Previous takeaway")
        XCTAssertTrue(session.quickSummaryError?.contains(LLMOutputLimit.notice) == true,
                      session.quickSummaryError ?? "")
        XCTAssertThrowsError(try MobileSession.quickOutput("not json", prose: false, cutOff: false)) { error in
            XCTAssertFalse(error is LLMOutputLimitError)
        }
        XCTAssertEqual(try MobileSession.quickOutput("No key takeaway yet.", prose: true, cutOff: true),
                       "No key takeaway yet.")
    }
}
