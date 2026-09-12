import XCTest
@testable import ListenToMeCore

final class TranscriptCorrectionStorageTests: XCTestCase {
    func testOldSegmentsDecodeAndCorrectionsRoundTripAndExportOriginals() throws {
        let original = TranscriptSegment(source: .you, text: "Meeting goats", isFinal: true, start: 2, end: 5)
        let oldJSON = try JSONEncoder().encode(original)
        XCTAssertFalse(String(decoding: oldJSON, as: UTF8.self).contains("originalText"))
        XCTAssertNil(try JSONDecoder().decode(TranscriptSegment.self, from: oldJSON).originalText)
        let repaired = TranscriptSegment(id: original.id, source: .you, text: "Meeting notes", isFinal: true,
                                         start: 2, end: 5, originalText: original.text, correctionModel: "test-flash")
        XCTAssertEqual(try JSONDecoder().decode(TranscriptSegment.self, from: JSONEncoder().encode(repaired)), repaired)
        let export = SessionExporter.markdown(title: "Test", transcript: [repaired])
        XCTAssertTrue(export.contains("**You:** Meeting notes"))
        XCTAssertTrue(export.contains("Original: Meeting goats"))
        XCTAssertTrue(export.contains("AI correction: Meeting notes"))
    }
}
