import XCTest
@testable import ListenToMeCore

final class ConversationRemovalTests: XCTestCase {
    private struct Failure: Error {}
    private func record(_ id: String) -> SessionRecord {
        SessionRecord(id: id, title: id, date: Date(), transcript: "Private conversation", summary: "",
                      sourceImportID: "watch-\(id)")
    }

    func testRemovingOneConversationErasesOnlyItsOwnedDataAndKeepsOthers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root.appendingPathComponent("records"))
        try archive.save(record("A")); try archive.save(record("B"))
        let audioA = root.appendingPathComponent("A.m4a"), audioB = root.appendingPathComponent("B.m4a")
        try Data([1]).write(to: audioA); try Data([2]).write(to: audioB)
        var seen: ConversationDeletion?
        let result = try ConversationRemoval.remove(record("A"), from: archive, owners: [
            ConversationDataOwner("audio") { deletion in
                XCTAssertFalse(archive.contains(id: "A"), "Archive must be gone before its owners are erased")
                seen = deletion
                for id in deletion.ids { try FileManager.default.removeItem(at: root.appendingPathComponent(id + ".m4a")) }
            },
        ])
        XCTAssertEqual(try archive.all().map(\.id), ["B"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioA.path))
        XCTAssertEqual(try Data(contentsOf: audioB), Data([2]))
        XCTAssertEqual(seen, ConversationDeletion(ids: ["A"], sourceImportIDs: ["watch-A"]))
        XCTAssertNil(result.archiveWarning)
        XCTAssertEqual(result.failedOwners, [])
    }

    func testArchiveFailureDoesNotEraseOwnedData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root) // A file where an archive directory must be: deterministic failure.
        var removed = false
        XCTAssertThrowsError(try ConversationRemoval.remove(record("A"), from: SessionArchive(directory: root),
            owners: [ConversationDataOwner("audio") { _ in removed = true }]))
        XCTAssertFalse(removed)
    }

    func testOwnedDataFailureIsReportedWithoutPreventingOtherOwners() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root)
        try archive.save(record("A"))
        var indexed = Set(["A", "B"])
        let result = try ConversationRemoval.remove(record("A"), from: archive, owners: [
            ConversationDataOwner("saved audio") { _ in throw Failure() },
            ConversationDataOwner("search index") { deletion in indexed.subtract(deletion.ids) },
        ])
        XCTAssertFalse(archive.contains(id: "A"))
        XCTAssertEqual(indexed, ["B"])
        XCTAssertEqual(result.failedOwners, ["saved audio"])
        XCTAssertTrue(ConversationDataErasure.failureNote(result.failedOwners)?.contains("saved audio") == true)
    }
}
