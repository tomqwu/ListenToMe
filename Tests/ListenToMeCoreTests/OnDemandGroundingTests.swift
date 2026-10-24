import XCTest
@testable import ListenToMeCore

/// Issue #114: with Auto off (the default) an on-demand Quick/Deep answer used to read the last
/// 4,000 characters and no summary, invisibly. The budget now scales with the provider, a long
/// meeting keeps the latest summary or its opening, and the pane says what was used.
final class OnDemandGroundingTests: XCTestCase {
    /// One ~200-character line per minute, timestamped, for `minutes` minutes.
    private func meeting(minutes: Int, label: String? = nil) -> [TranscriptSegment] {
        (0..<minutes).map { minute in
            var segment = TranscriptSegment(
                source: minute.isMultiple(of: 2) ? .others : .you,
                text: "Minute \(minute): " + String(repeating: "talk ", count: 38), isFinal: true,
                start: Double(minute * 60), end: Double(minute * 60 + 59))
            segment.speakerName = label
            return segment
        }
    }

    private func cost(_ segments: [TranscriptSegment]) -> Int {
        segments.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) }
    }

    // MARK: - Budget

    func testBudgetScalesWithTheProvider() {
        XCTAssertEqual(OnDemandGrounding.transcriptBudget(for: .answerQuestion, kind: .quick, limit: nil),
                       OnDemandGrounding.quickTranscriptCharacters)
        XCTAssertEqual(OnDemandGrounding.transcriptBudget(for: .clarify, kind: .deep, limit: nil),
                       OnDemandGrounding.deepTranscriptCharacters)
        XCTAssertGreaterThan(OnDemandGrounding.quickTranscriptCharacters, 4_000, "Larger than the old window")
        XCTAssertGreaterThan(OnDemandGrounding.deepTranscriptCharacters, OnDemandGrounding.quickTranscriptCharacters)
        // A provider with a declared window is asked for all of it; PromptBudget decides what fits.
        XCTAssertEqual(OnDemandGrounding.transcriptBudget(for: .answerQuestion, kind: .quick,
                                                          limit: PromptBudget.appleIntelligenceCharacters),
                       PromptBudget.appleIntelligenceCharacters)
        for kind in [PromptBuilder.Kind.quick, .deep] {
            XCTAssertEqual(OnDemandGrounding.transcriptBudget(for: .recap, kind: kind, limit: nil),
                           OnDemandGrounding.wholeConversationCharacters)
            XCTAssertEqual(OnDemandGrounding.transcriptBudget(for: .actionItems, kind: kind, limit: 8_000),
                           OnDemandGrounding.wholeConversationCharacters)
        }
    }

    // MARK: - Selection

    func testAConversationThatFitsIsSentWholeWithoutANotice() {
        let lines = meeting(minutes: 5)
        let selection = OnDemandGrounding.select(lines, budget: cost(lines), hasSummary: false)
        XCTAssertEqual(selection.shape, .whole)
        XCTAssertEqual(selection.segments, lines)
        XCTAssertNil(selection.notice(summaryName: "the Listener summary"))
        XCTAssertNil(selection.promptNote)
        XCTAssertEqual(OnDemandGrounding.select([], budget: 0, hasSummary: false).shape, .whole)
    }

    /// The issue's scenario: 45 minutes, Auto off, no summary. The minute-8 pricing decision is in
    /// the opening the excerpt keeps when the budget allows; the latest question is always there.
    func testWithoutASummaryALongMeetingKeepsItsOpeningAndItsLatestSpeech() {
        let lines = meeting(minutes: 45)
        let budget = 4_000
        let selection = OnDemandGrounding.select(lines, budget: budget, hasSummary: false)
        XCTAssertEqual(selection.shape, .openingAndRecent)
        XCTAssertEqual(selection.segments.first, lines.first)
        XCTAssertEqual(selection.segments.last, lines.last)
        XCTAssertLessThanOrEqual(cost(selection.segments), budget)
        XCTAssertLessThanOrEqual(cost(Array(selection.segments.prefix(selection.openingCount))),
                                 budget / OnDemandGrounding.openingShareDivisor)
        XCTAssertEqual(selection.segments, lines.filter(selection.segments.contains), "Lines stay in order")
        let notice = selection.notice(summaryName: "the Listener summary") ?? ""
        XCTAssertTrue(notice.hasPrefix("Using the opening ~\(selection.openingMinutes) min and the last "
                                       + "~\(selection.recentMinutes) min of the conversation"), notice)
        XCTAssertTrue(notice.contains("~\(selection.omittedMinutes) min in between left out"), notice)
        XCTAssertGreaterThan(selection.omittedMinutes, 20)
        XCTAssertTrue(selection.promptNote?.contains("first \(selection.openingCount) lines") == true)
    }

    func testWithASummaryOnlyTheLatestSpeechIsSentAndTheSummaryIsNamed() {
        let lines = meeting(minutes: 45)
        let selection = OnDemandGrounding.select(lines, budget: 4_000, hasSummary: true)
        XCTAssertEqual(selection.shape, .summaryAndRecent)
        XCTAssertEqual(selection.openingCount, 0)
        XCTAssertEqual(selection.segments.last, lines.last)
        XCTAssertNotEqual(selection.segments.first, lines.first)
        XCTAssertEqual(selection.notice(summaryName: "your Summary"),
                       "Using your Summary and the last ~\(selection.recentMinutes) min of the conversation.")
        XCTAssertTrue(selection.promptNote?.contains("summary covers what came before") == true)
    }

    /// A budget too small for any opening line still answers from the latest speech, and says so.
    func testATinyBudgetKeepsTheLatestLine() {
        let lines = meeting(minutes: 10)
        let selection = OnDemandGrounding.select(lines, budget: 300, hasSummary: false)
        XCTAssertEqual(selection.shape, .recent)
        XCTAssertEqual(selection.segments, [lines.last!])
        XCTAssertEqual(selection.notice(summaryName: "x"), "Using the last ~1 min of the conversation.")
        XCTAssertTrue(selection.promptNote?.contains("earlier speech was left out") == true)
        let none = OnDemandGrounding.select(lines, budget: 0, hasSummary: false)
        XCTAssertEqual(none.segments, [lines.last!], "The latest line is always kept")
    }

    /// An oversized latest line cannot be dropped; when that leaves nothing out, nothing is claimed.
    func testOnlyAnOversizedLatestLineIsNotAnExcerpt() {
        let short = TranscriptSegment(source: .you, text: "Hi.", isFinal: true, start: 0, end: 1)
        let long = TranscriptSegment(source: .others, text: String(repeating: "x", count: 900), isFinal: true,
                                     start: 1, end: 60)
        let selection = OnDemandGrounding.select([short, long], budget: 400, hasSummary: false)
        XCTAssertEqual(selection.shape, .whole)
        XCTAssertEqual(selection.segments, [short, long])
    }

    func testMinutesComeFromTimestampsOrFromLength() {
        XCTAssertEqual(OnDemandGrounding.minutes([]), 0)
        XCTAssertEqual(OnDemandGrounding.minutes(meeting(minutes: 5)), 5)
        let untimed = (0..<4).map { _ in
            TranscriptSegment(source: .others, text: String(repeating: "y", count: 850), isFinal: true, start: 0, end: 0)
        }
        XCTAssertEqual(OnDemandGrounding.minutes(untimed), 4)
        XCTAssertEqual(OnDemandGrounding.minutes([TranscriptSegment(source: .you, text: "a", isFinal: true,
                                                                     start: 0, end: 0)]), 1, "Never below 1")
    }

    func testEveryPromptNoteFitsItsReserve() {
        let lines = meeting(minutes: 600)
        for hasSummary in [false, true] {
            for budget in [0, 300, 4_000, 40_000] {
                let note = OnDemandGrounding.select(lines, budget: budget, hasSummary: hasSummary).promptNote ?? ""
                XCTAssertLessThanOrEqual(note.count + 2, OnDemandGrounding.promptNoteReserve, note)
            }
        }
    }

    /// The note is the app's own instruction, so it sits outside the data fence (#140), and a blank
    /// one is dropped like every other optional block.
    func testThePromptNoteSitsOutsideTheTranscriptFence() {
        let line = TranscriptSegment(source: .others, text: "Hello", isFinal: true, start: 0, end: 1)
        let context = ContextEngine.context(messages: [line], notes: "  ", summary: "\n",
                                            transcriptNote: "  The transcript is an excerpt.  ")
        XCTAssertNil(context.notes)
        XCTAssertNil(context.summary)
        XCTAssertEqual(context.transcriptNote, "The transcript is an excerpt.")
        let user = PromptBuilder.build(context: context, action: .answerQuestion).messages[0].content
        let fenceEnd = user.range(of: "</transcript>")!.upperBound
        XCTAssertTrue(user[fenceEnd...].contains("The transcript is an excerpt."))
        XCTAssertFalse(user[..<fenceEnd].contains("The transcript is an excerpt."))
        let plain = PromptBuilder.buildDeep(context: ContextEngine.context(messages: [line], notes: nil),
                                            action: .answerQuestion).messages[0].content
        XCTAssertFalse(plain.contains("excerpt"))
    }

    // MARK: - One-shot excerpt (iOS Quick and Deep)

    /// The on-device budget matches the check AppleIntelligenceProvider applies before generating.
    func testOneShotBudgetLeavesRoomForTheSystemPromptAndTheAnswer() {
        XCTAssertEqual(OnDemandGrounding.oneShotBudget(window: nil, system: "s"), OnDemandGrounding.oneShotCharacters)
        let system = String(repeating: "s", count: 900)
        XCTAssertEqual(OnDemandGrounding.oneShotBudget(window: PromptBudget.appleIntelligenceCharacters, system: system),
                       PromptBudget.appleIntelligenceCharacters - PromptBudget.answerReserve - 900)
        XCTAssertEqual(OnDemandGrounding.oneShotBudget(window: 1_000, system: system), PromptBudget.minimumTranscript)
    }

    func testAnExcerptThatFitsSendsEverythingAndNoSummary() {
        let lines = meeting(minutes: 3)
        let excerpt = OnDemandGrounding.excerpt(notes: "Budget review", segments: lines, summary: "Old summary",
                                                budget: 60_000)
        XCTAssertEqual(excerpt.selection.shape, .whole)
        XCTAssertNil(excerpt.summary)
        XCTAssertTrue(excerpt.transcript.hasPrefix("Notes: Budget review\n"))
        XCTAssertEqual(excerpt.userMessage, PromptData.block("transcript", excerpt.transcript))
    }

    /// Long notes over a short conversation: every line still goes, the notes are cut and the panel
    /// says so, and no summary stands in for speech that was all sent.
    func testOverlongNotesAreShortenedVisiblyWhileEveryLineIsSent() {
        let lines = meeting(minutes: 2)
        let excerpt = OnDemandGrounding.excerpt(notes: String(repeating: "n", count: 9_000), segments: lines,
                                                summary: "Earlier summary", budget: 4_000)
        XCTAssertEqual(excerpt.selection.shape, .whole)
        XCTAssertNil(excerpt.summary)
        XCTAssertTrue(excerpt.notesShortened)
        XCTAssertEqual(excerpt.notice(summaryName: "your Summary"), "Your notes were shortened to fit.")
        XCTAssertLessThanOrEqual(excerpt.userMessage.count, 4_000)
        let fits = OnDemandGrounding.excerpt(notes: "Short", segments: lines, summary: "", budget: 4_000)
        XCTAssertNil(fits.notice(summaryName: "your Summary"))
    }

    func testALongConversationIsExcerptedWithinTheBudget() {
        let lines = meeting(minutes: 60, label: "Alexandra Petrova")
        for budget in [1_500, 5_000, 6_000, 10_000] {
            for summary in ["", "We agreed on $40 per seat at minute 8."] {
                let excerpt = OnDemandGrounding.excerpt(notes: String(repeating: "note ", count: 400),
                                                        segments: lines, summary: summary, budget: budget)
                XCTAssertLessThanOrEqual(excerpt.userMessage.count, budget, "budget \(budget), summary \(!summary.isEmpty)")
                XCTAssertNotEqual(excerpt.selection.shape, .whole)
                XCTAssertTrue(excerpt.transcript.hasSuffix(QuickSummaryContext.attributed(lines.last!)))
                XCTAssertTrue(excerpt.transcript.hasPrefix("Notes: note"))
                if summary.isEmpty {
                    XCTAssertNil(excerpt.summary)
                } else {
                    XCTAssertEqual(excerpt.selection.shape, .summaryAndRecent)
                    XCTAssertTrue(excerpt.userMessage.contains(PromptData.block("summary", summary)))
                }
                if let note = excerpt.selection.promptNote { XCTAssertTrue(excerpt.userMessage.contains(note)) }
            }
        }
    }
}

/// The macOS panes: what reaches the model and what the pane says.
@MainActor
final class OnDemandGroundingSessionTests: XCTestCase {
    private func makeSession(limit: Int?) -> (MeetingSession, ConversationStore, RecordingProvider) {
        let store = ConversationStore()
        let provider = RecordingProvider(deltas: ["ok"], maxPromptCharacters: limit)
        let session = MeetingSession(
            store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "L", .quick: "Q", .deep: "D"], clock: { 0 })
        return (session, store, provider)
    }

    /// 45 minutes of ~200-character lines, one per minute, with the pricing decision at minute 2.
    private func fortyFiveMinuteMeeting(_ store: ConversationStore, lineLength: Int = 38) {
        for minute in 0..<45 {
            let text = minute == 2 ? "Pricing decision: we agreed on forty dollars per seat."
                : "Minute \(minute): " + String(repeating: "talk ", count: lineLength)
            store.apply(TranscriptSegment(source: minute.isMultiple(of: 2) ? .others : .you, text: text,
                                          isFinal: true, start: Double(minute * 60), end: Double(minute * 60 + 59)))
        }
        store.apply(TranscriptSegment(source: .others, text: "So, what did we agree on pricing earlier?",
                                      isFinal: true, start: 2_700, end: 2_705))
    }

    private func characters(_ request: LLMRequest?) -> Int {
        guard let request else { return 0 }
        return request.system.count + request.messages.reduce(0) { $0 + $1.content.count }
    }

    /// Unlimited providers (Ollama, cloud) now read far more than 4,000 characters: this whole
    /// 45-minute meeting (~9,500 characters) fits, so nothing is claimed.
    func testAnUnlimitedProviderReadsTheWholeMeetingWithAutoOff() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store)
        XCTAssertFalse(session.autoSummaryEnabled)
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains("Pricing decision"), "The minute-2 decision reaches the answer")
        XCTAssertTrue(user.contains("what did we agree on pricing earlier"))
        XCTAssertTrue(session.roleNotices(.quick).isEmpty)
    }

    /// A meeting longer than the Quick budget keeps its opening and its latest speech, says so in
    /// the pane, and tells the model the transcript is an excerpt.
    func testALongerMeetingIsExcerptedVisibly() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)   // ~27,000 characters
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains("Pricing decision"), "The opening is kept when there is no summary")
        XCTAssertTrue(user.contains("what did we agree on pricing earlier"))
        XCTAssertTrue(user.contains("The transcript is an excerpt"))
        XCTAssertTrue(session.roleNotices(.quick).first?.hasPrefix("Using the opening ~") == true,
                      session.roleNotices(.quick).description)
        // Deep reads twice as much, so the same meeting fits it whole.
        await session.respondDeep(.answerQuestion)
        XCTAssertTrue(session.roleNotices(.deep).isEmpty)
        XCTAssertTrue(session.roleNotices(.quick).first?.hasPrefix("Using the opening") == true)
    }

    func testTheListenerSummaryIsReusedWhenItExists() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        session.lastCompletedListenerSummary = "Earlier: pricing agreed at $40 per seat."
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains("Earlier: pricing agreed at $40 per seat."))
        XCTAssertTrue(user.contains("the meeting summary covers what came before"))
        XCTAssertTrue(session.roleNotices(.quick).first?.hasPrefix("Using the Listener summary and the last ~") == true)
    }

    /// Apple Intelligence: everything that fits the ~4k-token window, never more, and visible.
    func testAnAppleSizedWindowIsFilledButNeverExceeded() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fortyFiveMinuteMeeting(store)
        session.notes = String(repeating: "note ", count: 200)
        session.responseLanguage = "Simplified Chinese"
        for action in [ResponseAction.answerQuestion, .draftReply, .recap] {
            await session.respondQuick(action)
            XCTAssertLessThanOrEqual(characters(provider.lastRequest), limit, "quick \(action)")
            await session.respondDeep(action)
            XCTAssertLessThanOrEqual(characters(provider.lastRequest), limit, "deep \(action)")
            XCTAssertTrue(session.roleNotices(.deep).first?.hasPrefix("Using the") == true)
        }
        // More than the old 2,000 finalized characters the 4,000-character window actually allowed.
        XCTAssertGreaterThan(provider.lastUser?.count ?? 0, 4_000)
        XCTAssertNotNil(session.promptTruncationNotice)
    }

    func testSwitchingModelClearsThatPanesGroundingLine() async {
        let (session, store, _) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        await session.respondQuick(.answerQuestion)
        XCTAssertFalse(session.roleNotices(.quick).isEmpty)
        session.setModel(.quick, "other")
        XCTAssertTrue(session.roleNotices(.quick).isEmpty)
    }

    /// Unfinalized speech still reaches the answer, and no longer halves the finalized window.
    func testProvisionalSpeechIsKeptAlongsideTheFinalizedWindow() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store)
        store.apply(TranscriptSegment(source: .others, text: "and one more thing about the rollout plan",
                                      isFinal: false, start: 2_706, end: 2_708))
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains("(provisional) and one more thing"))
        XCTAssertTrue(user.contains("Pricing decision"))
    }
}
