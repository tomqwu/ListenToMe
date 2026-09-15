import XCTest
@testable import ListenToMeCore

final class SessionSearchTests: XCTestCase {
    private func record(
        _ id: String, title: String = "", summary: String = "", transcript: String = "",
        segments: [TranscriptSegment]? = nil, notes: String? = nil, date: Date
    ) -> SessionRecord {
        SessionRecord(id: id, title: title, date: date, transcript: transcript, summary: summary,
                      segments: segments, notes: notes)
    }

    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testEmptyQueryReturnsAllSortedByDateDescending() {
        let older = record("a", title: "Alpha", date: base)
        let newer = record("b", title: "Beta", date: base.addingTimeInterval(100))
        let result = SessionSearch.search([older, newer], query: "")
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testWhitespaceOnlyQueryTreatedAsEmpty() {
        let older = record("a", title: "Alpha", date: base)
        let newer = record("b", title: "Beta", date: base.addingTimeInterval(100))
        let result = SessionSearch.search([older, newer], query: "   \n  ")
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testSingleTermRanksByFrequency() {
        let once = record("once", transcript: "we discussed the budget", date: base.addingTimeInterval(100))
        let thrice = record("thrice", transcript: "budget budget budget", date: base)
        let result = SessionSearch.search([once, thrice], query: "budget")
        // Higher term frequency wins despite the older date.
        XCTAssertEqual(result.map(\.id), ["thrice", "once"])
    }

    func testFrequencyTieBrokenByMostRecentDate() {
        let older = record("older", transcript: "budget", date: base)
        let newer = record("newer", transcript: "budget", date: base.addingTimeInterval(100))
        let result = SessionSearch.search([older, newer], query: "budget")
        XCTAssertEqual(result.map(\.id), ["newer", "older"])
    }

    func testMultiTermRequiresAllTerms() {
        let both = record("both", title: "release", summary: "ship the release plan", date: base)
        let missing = record("missing", title: "release", summary: "ship it", date: base)
        let result = SessionSearch.search([both, missing], query: "release plan")
        XCTAssertEqual(result.map(\.id), ["both"])
    }

    func testTermsMatchAcrossTitleSummaryAndTranscript() {
        let spread = record("spread", title: "release", summary: "ship", transcript: "the plan", date: base)
        let result = SessionSearch.search([spread], query: "release ship plan")
        XCTAssertEqual(result.map(\.id), ["spread"])
    }

    func testNoMatchesReturnsEmpty() {
        let rec = record("a", transcript: "hello world", date: base)
        XCTAssertTrue(SessionSearch.search([rec], query: "missing").isEmpty)
    }

    func testCaseInsensitive() {
        let rec = record("a", title: "Budget Review", date: base)
        XCTAssertEqual(SessionSearch.search([rec], query: "BUDGET review").map(\.id), ["a"])
    }

    // MARK: - Normalization (#139)

    func testDiacriticInsensitiveBothWays() {
        let accented = record("a", transcript: "we met at the café in Zürich with José", date: base)
        XCTAssertEqual(SessionSearch.search([accented], query: "cafe").map(\.id), ["a"])
        XCTAssertEqual(SessionSearch.search([accented], query: "zurich jose").map(\.id), ["a"])
        let plain = record("b", transcript: "we met at the cafe", date: base)
        XCTAssertEqual(SessionSearch.search([plain], query: "café").map(\.id), ["b"])
    }

    func testFullWidthInsensitive() {
        let wide = record("a", transcript: "ＡＩ の議論", date: base)
        XCTAssertEqual(SessionSearch.search([wide], query: "AI").map(\.id), ["a"])
        let narrow = record("b", transcript: "AI discussion", date: base)
        XCTAssertEqual(SessionSearch.search([narrow], query: "ＡＩ").map(\.id), ["b"])
    }

    func testCJKSubstringMatchesWithoutWordBoundaries() {
        let cjk = record("a", title: "定例会議", transcript: "議事録をまとめる", date: base)
        XCTAssertEqual(SessionSearch.search([cjk], query: "会議").map(\.id), ["a"])
        XCTAssertEqual(SessionSearch.search([cjk], query: "会議 議事録").map(\.id), ["a"])
        XCTAssertTrue(SessionSearch.search([cjk], query: "予算").isEmpty)
    }

    func testTabAndCarriageReturnSeparateTerms() {
        let rec = record("a", title: "budget", transcript: "Q3 targets", date: base)
        XCTAssertEqual(SessionSearch.search([rec], query: "budget\tQ3").map(\.id), ["a"])
        XCTAssertEqual(SessionSearch.search([rec], query: "budget\r\nQ3").map(\.id), ["a"])
        XCTAssertEqual(SessionSearch.search([rec], query: "\t \r\n ").map(\.id), ["a"])
    }

    func testWholeWordMatchesOutrankSubstringMatches() {
        let inside = record("inside", transcript: "start the party, restart the chart", date: base.addingTimeInterval(100))
        let whole = record("whole", transcript: "art", date: base)
        XCTAssertEqual(SessionSearch.search([inside, whole], query: "art").map(\.id), ["whole", "inside"])
    }

    func testSpeakerPrefixedTranscriptLinesDoNotCreateFalseMatches() {
        let segment = TranscriptSegment(source: .you, text: "the budget is fine", isFinal: true, start: 0, end: 1)
        let rec = record("a", transcript: "You: the budget is fine", segments: [segment], date: base)
        XCTAssertTrue(SessionSearch.search([rec], query: "you").isEmpty)
        XCTAssertEqual(SessionSearch.search([rec], query: "budget").map(\.id), ["a"])
    }

    func testSpeakerNamesAreSearchable() {
        var segment = TranscriptSegment(source: .others, text: "I will ship", isFinal: true, start: 0, end: 1)
        segment.speakerName = "Alice"
        let rec = record("a", segments: [segment], date: base)
        XCTAssertEqual(SessionSearch.search([rec], query: "alice ship").map(\.id), ["a"])
    }

    func testNotesAreSearchable() {
        let rec = record("a", notes: "shared agenda from the iOS share sheet", date: base)
        XCTAssertEqual(SessionSearch.search([rec], query: "agenda").map(\.id), ["a"])
    }
}
