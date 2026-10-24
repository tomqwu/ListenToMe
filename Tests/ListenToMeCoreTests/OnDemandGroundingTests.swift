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

    /// A summary stands in only for the lines it is known to cover. Everything said since fits here,
    /// so all of it is sent and the notice names the summary's span.
    func testASummaryCoversOnlyTheLinesItRead() {
        let lines = meeting(minutes: 45)
        let selection = OnDemandGrounding.select(lines, budget: 4_000, hasSummary: true, coveredCount: 30)
        XCTAssertEqual(selection.shape, .summaryAndRecent)
        XCTAssertEqual(selection.coveredCount, 30)
        XCTAssertEqual(selection.segments, Array(lines[30...]), "Everything since the summary, nothing before")
        XCTAssertEqual(selection.notice(summaryName: "your Summary"),
                       "Using your Summary of the first ~\(selection.coveredMinutes) min and everything said since "
                       + "(~\(selection.recentMinutes) min).")
        XCTAssertEqual(selection.coveredMinutes, 30)
        XCTAssertTrue(selection.promptNote?.contains("covers the first 30 lines") == true)
        XCTAssertFalse(selection.unverifiedSummary)
    }

    /// The review's case: a summary from minute 10 and a question at minute 50. The prompt must not
    /// claim the summary covers 10–32; the speech right after the summary and the latest speech are
    /// sent, and the gap is named.
    func testAStaleSummaryKeepsTheSpeechAfterItAndNamesTheGap() {
        let lines = meeting(minutes: 50)
        let selection = OnDemandGrounding.select(lines, budget: 4_000, hasSummary: true, coveredCount: 10)
        XCTAssertEqual(selection.shape, .openingAndRecent)
        XCTAssertEqual(selection.coveredCount, 10)
        XCTAssertEqual(selection.segments.first, lines[10], "The head starts where the summary stops")
        XCTAssertEqual(selection.segments.last, lines.last)
        XCTAssertLessThanOrEqual(cost(selection.segments), 4_000)
        let notice = selection.notice(summaryName: "the Listener summary") ?? ""
        XCTAssertTrue(notice.hasPrefix("Using the Listener summary of the first ~10 min, the ~"), notice)
        XCTAssertTrue(notice.contains("min in between left out"), notice)
        let note = selection.promptNote ?? ""
        XCTAssertTrue(note.contains("covers the first 10 lines"), note)
        XCTAssertTrue(note.contains("the speech right after the summary"), note)
        XCTAssertTrue(note.contains("was left out to fit"), note)
    }

    /// A summary of unknown coverage (cut off, shortened, restored) is sent but claims nothing: the
    /// opening is kept as if there were none, and the notice says a summary is included too.
    func testASummaryOfUnknownCoverageClaimsNothing() {
        let lines = meeting(minutes: 45)
        let selection = OnDemandGrounding.select(lines, budget: 4_000, hasSummary: true, coveredCount: 0)
        XCTAssertEqual(selection.shape, .openingAndRecent)
        XCTAssertEqual(selection.coveredCount, 0)
        XCTAssertTrue(selection.unverifiedSummary)
        XCTAssertEqual(selection.segments.first, lines.first)
        XCTAssertTrue(selection.notice(summaryName: "x")?.hasSuffix("An earlier summary is included too.") == true)
        XCTAssertTrue(selection.promptNote?.contains("may not cover the speech left out") == true)
        XCTAssertFalse(selection.promptNote?.contains("covers the first") == true)
    }

    /// A summary that covers every line still leaves the latest one verbatim.
    func testASummaryCoveringEverythingStillSendsTheLatestLine() {
        let lines = meeting(minutes: 30)
        let selection = OnDemandGrounding.select(lines, budget: 1_000, hasSummary: true, coveredCount: 30)
        XCTAssertEqual(selection.segments, [lines.last!])
        XCTAssertEqual(selection.shape, .summaryAndRecent)
        XCTAssertEqual(selection.coveredCount, 29)
        XCTAssertEqual(OnDemandGrounding.coveredPrefix(of: lines, ids: Set(lines.prefix(5).map(\.id))), 5)
        XCTAssertEqual(OnDemandGrounding.coveredPrefix(of: lines, ids: Set(lines.dropFirst().map(\.id))), 0,
                       "Coverage is a prefix: a gap at the start covers nothing")
    }

    /// A budget too small for any opening line still answers from the latest speech, and says so.
    func testATinyBudgetKeepsTheLatestLine() {
        let lines = meeting(minutes: 10)
        let selection = OnDemandGrounding.select(lines, budget: 300, hasSummary: false)
        XCTAssertEqual(selection.shape, .recent)
        XCTAssertEqual(selection.segments, [lines.last!])
        XCTAssertEqual(selection.notice(summaryName: "x"),
                       "Using the last ~1 min of the conversation (~9 min in between left out).")
        XCTAssertTrue(selection.promptNote?.contains("only the most recent ~1 min") == true)
        XCTAssertTrue(OnDemandGrounding.select(lines, budget: 0, hasSummary: false).segments.isEmpty,
                      "Nothing at all fits a zero budget")
    }

    /// An oversized latest line no longer overruns the budget (the guarantee the old window kept): the
    /// opening goes first, then the line keeps its most recent words, and the notice says so.
    func testAnOversizedLatestLineIsShortenedToFit() {
        let short = TranscriptSegment(source: .you, text: "Hi.", isFinal: true, start: 0, end: 1)
        let long = TranscriptSegment(source: .others, text: String(repeating: "x", count: 899) + "END",
                                     isFinal: true, start: 1, end: 60)
        let selection = OnDemandGrounding.select([short, long], budget: 400, hasSummary: false)
        XCTAssertEqual(selection.shape, .recent)
        XCTAssertTrue(selection.latestShortened)
        XCTAssertEqual(selection.segments.count, 1)
        XCTAssertTrue(selection.segments[0].text.hasSuffix("END"), "The most recent words are kept")
        XCTAssertLessThanOrEqual(cost(selection.segments), 400)
        XCTAssertTrue(selection.notice(summaryName: "x")?.contains("The latest line was shortened.") == true)
        XCTAssertTrue(selection.promptNote?.contains("shortened") == true)
    }

    /// Property: whatever the lines, labels, summary coverage and budget, the selection never costs
    /// more than the budget, keeps the lines in order, and its note fits its reserve.
    func testTheSelectionNeverExceedsItsBudget() {
        var generator = SeededGenerator(seed: 114)
        for _ in 0..<400 {
            let count = Int.random(in: 1...60, using: &generator)
            var clock = 0.0
            var lines: [TranscriptSegment] = []
            for _ in 0..<count {
                let length = Int.random(in: 1...(Bool.random(using: &generator) ? 300 : 3_000), using: &generator)
                let duration = Double.random(in: 0...90, using: &generator)
                var line = TranscriptSegment(source: Bool.random(using: &generator) ? .you : .others,
                                             text: String(repeating: "w", count: length), isFinal: true,
                                             start: clock, end: clock + duration)
                if Bool.random(using: &generator) {
                    line.speakerName = String(repeating: "N", count: Int.random(in: 1...40, using: &generator))
                }
                lines.append(line)
                clock += duration
            }
            let budget = Int.random(in: 0...12_000, using: &generator)
            let hasSummary = Bool.random(using: &generator)
            let covered = Int.random(in: 0...count, using: &generator)
            let selection = OnDemandGrounding.select(lines, budget: budget, hasSummary: hasSummary,
                                                     coveredCount: covered)
            XCTAssertLessThanOrEqual(cost(selection.segments), budget, "budget \(budget), \(count) lines")
            let ids = selection.segments.map(\.id)
            XCTAssertEqual(ids, lines.map(\.id).filter(ids.contains), "In order")
            XCTAssertLessThanOrEqual((selection.promptNote?.count ?? 0) + 2, OnDemandGrounding.promptNoteReserve)
        }
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
                                                        segments: lines, summary: summary,
                                                        summaryCoveredIDs: Set(lines.prefix(20).map(\.id)),
                                                        budget: budget)
                XCTAssertLessThanOrEqual(excerpt.userMessage.count, budget, "budget \(budget)")
                XCTAssertNotEqual(excerpt.selection.shape, .whole)
                XCTAssertTrue(excerpt.transcript.hasPrefix("Notes: note"))
                if summary.isEmpty {
                    XCTAssertNil(excerpt.summary)
                    XCTAssertEqual(excerpt.selection.coveredCount, 0)
                } else {
                    XCTAssertEqual(excerpt.selection.coveredCount, 20)
                    XCTAssertTrue(excerpt.userMessage.contains(PromptData.block("summary", summary)))
                }
                if let note = excerpt.selection.promptNote { XCTAssertTrue(excerpt.userMessage.contains(note)) }
            }
        }
    }

    /// Only the end of a long summary fits: its decisions and actions are kept, the panel says so, and
    /// a shortened summary is never claimed to cover anything.
    func testALongSummaryKeepsItsEndAndSaysSo() {
        let lines = meeting(minutes: 60)
        let summary = String(repeating: "Background. ", count: 400) + "Decision: $40 per seat. Action: Sarah sends terms."
        let excerpt = OnDemandGrounding.excerpt(notes: "", segments: lines, summary: summary,
                                                summaryCoveredIDs: Set(lines.prefix(30).map(\.id)), budget: 5_000)
        XCTAssertTrue(excerpt.summaryShortened)
        XCTAssertTrue(excerpt.summary?.hasSuffix("Action: Sarah sends terms.") == true)
        XCTAssertEqual(excerpt.selection.coveredCount, 0)
        XCTAssertTrue(excerpt.notice(summaryName: "your Summary")?.contains("Only the end of the summary fit.") == true)
        XCTAssertLessThanOrEqual(excerpt.userMessage.count, 5_000)
    }

    /// Notes over a conversation with no transcript keep all the room there is, not a quarter of it.
    func testNotesUseTheRoomTheSpeechLeaves() {
        let notes = String(repeating: "n", count: 3_000)
        let excerpt = OnDemandGrounding.excerpt(notes: notes, segments: [], summary: "", budget: 2_500)
        XCTAssertTrue(excerpt.notesShortened)
        XCTAssertGreaterThan(excerpt.transcript.count, 2_000, "More than a quarter of the budget")
        XCTAssertLessThanOrEqual(excerpt.userMessage.count, 2_500)
    }

    /// Property: the whole user message never exceeds the budget, including fences that escape "</".
    func testTheExcerptNeverExceedsItsBudget() {
        var generator = SeededGenerator(seed: 215)
        for _ in 0..<200 {
            let count = Int.random(in: 0...50, using: &generator)
            var lines: [TranscriptSegment] = []
            for index in 0..<count {
                let length = Int.random(in: 1...2_500, using: &generator)
                let text = Bool.random(using: &generator) ? String(repeating: "</t", count: length / 3 + 1)
                    : String(repeating: "w", count: length)
                lines.append(TranscriptSegment(source: .others, text: text, isFinal: true,
                                               start: Double(index * 30), end: Double(index * 30 + 29)))
            }
            let budget = Int.random(in: 1_000...12_000, using: &generator)
            let notes = String(repeating: "n", count: Int.random(in: 0...5_000, using: &generator))
            let summary = String(repeating: "s", count: Int.random(in: 0...4_000, using: &generator))
            let covered = Set(lines.prefix(Int.random(in: 0...count, using: &generator)).map(\.id))
            let excerpt = OnDemandGrounding.excerpt(notes: notes, segments: lines, summary: summary,
                                                    summaryCoveredIDs: covered, budget: budget)
            XCTAssertLessThanOrEqual(excerpt.userMessage.count, budget, "budget \(budget), \(count) lines")
        }
    }
}

/// A small deterministic generator, so the property tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
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
        XCTAssertTrue(user.contains("are the opening of the meeting"))
        XCTAssertTrue(session.roleNotices(.quick).first?.hasPrefix("Using the opening ~") == true,
                      session.roleNotices(.quick).description)
        // Deep reads twice as much, so the same meeting fits it whole.
        await session.respondDeep(.answerQuestion)
        XCTAssertTrue(session.roleNotices(.deep).isEmpty)
        XCTAssertTrue(session.roleNotices(.quick).first?.hasPrefix("Using the opening") == true)
    }

    /// The Listener summary stands in for exactly the lines its ledger says it read.
    func testTheListenerSummaryCoversWhatItsLedgerRead() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        session.lastCompletedListenerSummary = "Earlier: pricing agreed at $40 per seat."
        session.summarizedSegmentIDs = Set(store.utterances.prefix(30).map(\.id))
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains("Earlier: pricing agreed at $40 per seat."))
        XCTAssertTrue(user.contains("covers the first 30 lines"), user)
        XCTAssertFalse(user.contains("Pricing decision"), "Covered speech is not repeated")
        XCTAssertTrue(session.roleNotices(.quick).first?.hasPrefix("Using the Listener summary of the first ~30 min") == true,
                      session.roleNotices(.quick).description)
    }

    /// The review's case: Refresh at minute 10, Quick at minute 45. The summary is not claimed to
    /// cover minutes 10–45; the speech right after it is sent, and the gap is named.
    func testAStaleListenerSummaryIsNotClaimedToCoverLaterSpeech() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        session.lastCompletedListenerSummary = "First ten minutes: introductions."
        session.summarizedSegmentIDs = Set(store.utterances.prefix(10).map(\.id))
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertTrue(user.contains("covers the first 10 lines"), user)
        XCTAssertTrue(user.contains("Minute 10: "), "The speech right after the summary is kept")
        XCTAssertTrue(user.contains("was left out to fit"))
        let notice = session.roleNotices(.quick).first ?? ""
        XCTAssertTrue(notice.hasPrefix("Using the Listener summary of the first ~10 min, the ~"), notice)
        XCTAssertTrue(notice.contains("in between left out"), notice)
    }

    /// A Listener summary that stopped at the output limit is sent but never claimed as coverage.
    func testACutOffListenerSummaryIsNotTreatedAsCoverage() async {
        let (session, store, provider) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        session.lastCompletedListenerSummary = "Earlier: pricing agre"
        session.summarizedSegmentIDs = Set(store.utterances.map(\.id))
        session.listenerSummaryCutOff = true
        await session.respondQuick(.answerQuestion)
        let user = provider.lastUser ?? ""
        XCTAssertFalse(user.contains("covers the first"), user)
        XCTAssertTrue(user.contains("may not cover the speech left out"))
        XCTAssertTrue(user.contains("Pricing decision"), "The opening is kept instead")
        XCTAssertTrue(session.roleNotices(.quick).first?.hasSuffix("An earlier summary is included too.") == true)
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

    /// The guarantee the old window kept: one enormous final line — and an enormous unfinished one —
    /// never push an Apple-sized prompt past its window. The line keeps its most recent words.
    func testAnEnormousLatestLineStillFitsAnAppleSizedWindow() async {
        let limit = PromptBudget.appleIntelligenceCharacters
        let (session, store, provider) = makeSession(limit: limit)
        fortyFiveMinuteMeeting(store)
        store.apply(TranscriptSegment(source: .others, text: String(repeating: "long ", count: 6_000) + "FINAL WORDS",
                                      isFinal: true, start: 2_710, end: 2_900))
        store.apply(TranscriptSegment(source: .you, text: String(repeating: "live ", count: 6_000),
                                      isFinal: false, start: 2_901, end: 3_000))
        for action in [ResponseAction.answerQuestion, .recap, .actionItems] {
            await session.respondQuick(action)
            XCTAssertLessThanOrEqual(characters(provider.lastRequest), limit - PromptBudget.answerReserve, "quick \(action)")
            await session.respondDeep(action)
            XCTAssertLessThanOrEqual(characters(provider.lastRequest), limit - PromptBudget.answerReserve, "deep \(action)")
        }
        XCTAssertTrue(provider.lastUser?.contains("FINAL WORDS") == true)
        XCTAssertTrue(session.roleNotices(.deep).first?.contains("The latest line was shortened.") == true,
                      session.roleNotices(.deep).description)
    }

    /// The answer on screen is still the excerpt-grounded one after a model switch, so its line stays.
    func testSwitchingModelKeepsTheLineOfTheAnswerStillShown() async {
        let (session, store, _) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        await session.respondQuick(.answerQuestion)
        let notices = session.roleNotices(.quick)
        XCTAssertFalse(notices.isEmpty)
        session.setModel(.quick, "other")
        XCTAssertEqual(session.roleNotices(.quick), notices)
    }

    /// Review item 1: the automatic recap replacing (or Auto clearing) the Quick answer takes the
    /// answer's lines with it.
    func testTheRecapReplacingTheAnswerTakesItsNoticesWithIt() async {
        let (session, store, _) = makeSession(limit: nil)
        fortyFiveMinuteMeeting(store, lineLength: 120)
        await session.respondQuick(.answerQuestion)
        XCTAssertFalse(session.roleNotices(.quick).isEmpty)
        session.applyQuickRecap("- Pricing agreed.")
        XCTAssertFalse(session.roleNotices(.quick).isEmpty, "A fresh answer still holds the pane")
        session.dismissQuickAnswer()
        XCTAssertEqual(session.quickSuggestion, "- Pricing agreed.")
        XCTAssertTrue(session.roleNotices(.quick).isEmpty)
        session.setOutput(.quick, "")
        XCTAssertTrue(session.roleNotices(.quick).isEmpty)
    }

    /// Review item 3: a failed request that restores the previous answer restores that answer's own
    /// lines, not the failed request's; a failure that keeps partial text shows none.
    func testAFailedRequestNeverShowsItsNoticesOnTheRestoredAnswer() async {
        let store = ConversationStore()
        let provider = SwitchableProvider()
        let session = MeetingSession(
            store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "L", .quick: "Q", .deep: "D"], clock: { 0 })
        store.apply(TranscriptSegment(source: .others, text: "Short meeting?", isFinal: true, start: 0, end: 1))
        provider.events = [.content("Complete but cut"), .outputLimitReached]
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.roleNotices(.deep), [LLMOutputLimit.notice])

        fortyFiveMinuteMeeting(store, lineLength: 240)   // the next request is an excerpt…
        provider.events = []
        provider.failure = URLError(.networkConnectionLost)   // …that fails before any text
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.deepAnswer, "Complete but cut", "The previous answer is restored")
        XCTAssertEqual(session.roleNotices(.deep), [LLMOutputLimit.notice], "…with its own line, not the excerpt's")

        provider.events = [.content("Half an ans")]
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.deepAnswer, "Half an ans", "Partial text is kept")
        XCTAssertTrue(session.roleNotices(.deep).isEmpty, "A failed answer carries no grounding or cut-off line")
        XCTAssertNotNil(session.roleError(.deep))
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

/// Streams the events it is given, then fails with `failure` when one is set.
final class SwitchableProvider: LLMProvider, @unchecked Sendable {
    let id = "switchable"
    var events: [LLMStreamEvent] = []
    var failure: (any Error)?
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        LLMOutputLimit.textStream(streamEvents(request))
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let events = events, failure = failure
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if let failure { continuation.finish(throwing: failure) } else { continuation.finish() }
        }
    }
}
