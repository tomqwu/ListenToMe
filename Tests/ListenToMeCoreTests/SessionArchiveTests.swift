import XCTest
@testable import ListenToMeCore

final class SessionArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func record(_ id: String = "A", text: String = "Finalized speech") -> SessionRecord {
        SessionRecord(id: id, title: "Meeting", date: Date(timeIntervalSince1970: 123),
                      transcript: text, summary: "Decision", notes: "Context", isComplete: false)
    }

    func testCheckpointSurvivesReopeningAndUpsertsOneConversation() throws {
        let path = root.appendingPathComponent("history")
        try SessionArchive(directory: path).save(record())
        try SessionArchive(directory: path).save(record(text: "Finalized tail"))
        XCTAssertEqual(try SessionArchive(directory: path).all(), [record(text: "Finalized tail")])
    }

    func testNewConversationDoesNotOverwritePriorConversation() throws {
        let archive = SessionArchive(directory: root)
        try archive.save(record("A")); try archive.save(record("B"))
        XCTAssertEqual(Set(try archive.all().map(\.id)), ["A", "B"])
    }

    func testSpeakerIdentityAndAllConversationFieldsRoundTrip() throws {
        var segment = TranscriptSegment(source: .others, text: "I will ship", isFinal: true, start: 1, end: 4)
        segment.speakerID = "person-1"; segment.speakerName = "Alice"
        let full = SessionRecord(id: "full", title: "Plan", date: Date(), transcript: "Alice: I will ship",
                                 summary: "Ship", segments: [segment], notes: "Wednesday",
                                 quickSuggestion: "Confirm", deepAnswer: "Details", isComplete: true)
        let archive = SessionArchive(directory: root)
        try archive.save(full)
        XCTAssertEqual(try archive.all(), [full])
    }

    func testLegacyMigrationPreservesOriginalAndDoesNotResurrectClearedData() throws {
        let legacy = root.appendingPathComponent("sessions.json")
        try JSONEncoder().encode([record()]).write(to: legacy)
        let archive = SessionArchive(directory: root.appendingPathComponent("history"), legacyURL: legacy)
        XCTAssertEqual(try archive.all(), [record()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        try archive.clear()
        XCTAssertEqual(try archive.all(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testProductionClearAlsoDeletesOwnedLegacyCopy() throws {
        let legacy = root.appendingPathComponent("sessions.json")
        try JSONEncoder().encode([record()]).write(to: legacy)
        let archive = SessionArchive(directory: root.appendingPathComponent("history"), legacyURL: legacy,
                                     ownsLegacyFile: true)
        try archive.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try archive.all(), [])
    }

    func testOlderSchemaDecodesWithoutNewFields() throws {
        let data = Data(#"{"id":"old","title":"Old","date":0,"transcript":"hello","summary":""}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        XCTAssertNil(decoded.segments); XCTAssertNil(decoded.isComplete)
        XCTAssertEqual(decoded.transcript, "hello")
    }

    func testCorruptionIsReportedAndNeverOverwrittenAsEmptyHistory() throws {
        let legacy = root.appendingPathComponent("sessions.json")
        let damaged = Data("damaged".utf8)
        try damaged.write(to: legacy)
        let archive = SessionArchive(directory: root.appendingPathComponent("history"), legacyURL: legacy)
        XCTAssertThrowsError(try archive.all())
        XCTAssertThrowsError(try archive.save(record()))
        XCTAssertEqual(try Data(contentsOf: legacy), damaged)
    }

    func testFailedWriteLeavesPriorCheckpointReadable() throws {
        let archive = SessionArchive(directory: root)
        try archive.save(record())
        let blocked = root.appendingPathComponent("B.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        XCTAssertThrowsError(try archive.save(record("B")))
        let prior = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: root.appendingPathComponent("A.json")))
        XCTAssertEqual(prior, record())
    }

    func testInvalidIdentifierCannotEscapeArchive() throws {
        XCTAssertThrowsError(try SessionArchive(directory: root).save(record("../escape")))
    }

    func testDeleteOnlyRemovesSelectedSessionAndDoesNotRemigrateIt() throws {
        let legacy = root.appendingPathComponent("legacy.json")
        try JSONEncoder().encode([record("A"), record("B")]).write(to: legacy)
        let directory = root.appendingPathComponent("history")
        let archive = SessionArchive(directory: directory, legacyURL: legacy)
        try archive.delete(id: "A")
        try archive.delete(id: "A")
        XCTAssertEqual(try SessionArchive(directory: directory, legacyURL: legacy).all().map(\.id), ["B"])
        XCTAssertThrowsError(try archive.delete(id: "../legacy"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testHistoryHasNoSilentTwoHundredConversationLimit() throws {
        let archive = SessionArchive(directory: root)
        for index in 0..<205 { try archive.save(record(String(index))) }
        XCTAssertEqual(try archive.all().count, 205)
    }
}
