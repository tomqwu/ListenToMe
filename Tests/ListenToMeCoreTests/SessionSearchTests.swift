import XCTest
@testable import ListenToMeCore

final class SessionSearchTests: XCTestCase {
    private func record(
        _ id: String, title: String = "", summary: String = "", transcript: String = "",
        date: Date
    ) -> SessionRecord {
        SessionRecord(id: id, title: title, date: date, transcript: transcript, summary: summary)
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
}
