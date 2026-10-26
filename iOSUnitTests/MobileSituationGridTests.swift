import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileSituationGridTests: XCTestCase {
    func testRestoreSavePreservesGridUntilSummaryOrEvidenceChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = TranscriptSegment(source: .others, text: "We agreed to ship Friday.", isFinal: true, start: 1, end: 2)
        let json = #"""
        {"summary":"Release decision.","open":[],"todo":[],
        "decided":[{"text":"Ship Friday","quotes":["We agreed to ship Friday."]}]}
        """#
        let grid = try XCTUnwrap(SituationGrid.decode(json, segments: [line]))
        let record = SessionRecord(id: UUID().uuidString, title: "Meeting", date: Date(), transcript: line.text,
                                   summary: grid.markdown, segments: [line], hasIncompleteImport: true, situationGrid: grid)
        let session = MobileSession(storageDirectory: root)
        session.restore(record)
        XCTAssertEqual(session.currentRecord.situationGrid, grid)
        XCTAssertEqual(session.currentRecord.hasIncompleteImport, true)
        XCTAssertEqual(session.currentRecord.isComplete, false)
        session.notes = "More notes"
        XCTAssertEqual(session.currentRecord.situationGrid, grid)
        session.summary = "New summary"
        XCTAssertNil(session.currentRecord.situationGrid)
        session.restore(record)
        session.segments = []
        XCTAssertNil(session.currentRecord.situationGrid)
    }
}
