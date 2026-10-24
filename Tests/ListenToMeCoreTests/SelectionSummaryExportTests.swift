import XCTest
@testable import ListenToMeCore

/// Issue #234: saved selection summaries travel with the conversation into every export that carries
/// its other summaries — Markdown (and the readable text built from it), JSON and Save to folder notes.
final class SelectionSummaryExportTests: XCTestCase {
    private let summaries = [
        SelectionSummary(date: Date(timeIntervalSince1970: 1_000), start: 62, end: 75, lineCount: 2,
                         shortened: false, text: "- Ship Friday; QA Thursday."),
        SelectionSummary(date: Date(timeIntervalSince1970: 900), start: 0, end: 4, lineCount: 1,
                         shortened: true, text: "- Greetings.")
    ]

    private func record(_ summaries: [SelectionSummary]?) -> SessionRecord {
        SessionRecord(id: "sel-1", title: "Launch review", date: Date(timeIntervalSince1970: 0), transcript: "",
                      summary: "Recap", segments: [], selectionSummaries: summaries)
    }

    func testMarkdownListsThemAfterTheOtherSummaries() {
        let markdown = SessionExporter.markdown(for: record(summaries))
        XCTAssertTrue(markdown.contains("""
        ## Selection summaries

        ### 1:02–1:15 · 2 lines

        - Ship Friday; QA Thursday.

        ### 0:00–0:04 · 1 line

        - Greetings.
        """), markdown)
        XCTAssertLessThan(markdown.range(of: "Recap")!.lowerBound, markdown.range(of: "## Selection summaries")!.lowerBound)
        XCTAssertFalse(SessionExporter.markdown(for: record(nil)).contains("Selection summaries"))
    }

    func testJSONCarriesThemAndAnEmptyArrayOtherwise() throws {
        let json = SessionExporter.json(for: record(summaries))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let list = try XCTUnwrap(object["selectionSummaries"] as? [[String: Any]])
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0]["text"] as? String, "- Ship Friday; QA Thursday.")
        XCTAssertEqual(list[0]["start"] as? Double, 62)
        XCTAssertEqual(list[0]["end"] as? Double, 75)
        XCTAssertEqual(list[0]["lineCount"] as? Int, 2)
        XCTAssertEqual(list[1]["shortened"] as? Bool, true)
        XCTAssertEqual(list[0]["date"] as? String, "1970-01-01T00:16:40Z")
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SessionExporter.json(for: record(nil)).utf8))
            as? [String: Any])
        XCTAssertEqual((empty["selectionSummaries"] as? [Any])?.count, 0, "Every document has the same keys")
    }

    func testSaveToFolderNotesCarryThem() {
        let note = MarkdownVault.markdown(for: record(summaries))
        XCTAssertTrue(note.contains("## Selection summaries\n\n### 1:02–1:15 · 2 lines\n\n- Ship Friday; QA Thursday."), note)
        XCTAssertFalse(MarkdownVault.markdown(for: record(nil)).contains("Selection summaries"))
    }
}
