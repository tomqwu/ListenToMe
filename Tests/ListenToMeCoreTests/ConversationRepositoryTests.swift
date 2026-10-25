import XCTest
@testable import ListenToMeCore

@MainActor
final class ConversationRepositoryTests: XCTestCase {
    private func record(_ id: String, summary: String = "Summary") -> SessionRecord {
        SessionRecord(id: id, title: id, date: Date(), transcript: "Evidence", summary: summary)
    }

    func testSaveReplaceReloadAndClearPublishDurableSnapshotsInOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root)
        let repository = ConversationRepository(archive: archive)
        var snapshots: [[SessionRecord]] = []
        repository.recordsChanged = { change, records in
            snapshots.append(records)
            if case .saved(let saved) = change { XCTAssertTrue(archive.contains(id: saved.id)) }
        }
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertTrue(repository.add(record("one")))
        XCTAssertTrue(repository.add(record("one", summary: "Changed")))
        XCTAssertEqual(repository.known.count, 1)
        XCTAssertEqual(repository.all().first?.summary, "Changed")
        XCTAssertEqual(repository.completeIDs(), ["one"])
        XCTAssertTrue(repository.contains("one"))
        var ownerCalls = 0
        repository.dataOwners = [ConversationDataOwner("fake audio") { deletion in
            XCTAssertTrue(deletion.everything)
            XCTAssertFalse(archive.contains(id: "one"))
            ownerCalls += 1
            throw CocoaError(.fileWriteNoPermission)
        }]
        XCTAssertTrue(repository.clear(), "Archive removal succeeds independently of a secondary owner")
        XCTAssertEqual(ownerCalls, 1)
        XCTAssertTrue(repository.errorText?.contains("fake audio") == true)
        XCTAssertTrue(repository.known.isEmpty)
        XCTAssertEqual(snapshots.last, [])
        XCTAssertEqual(snapshots.first?.first?.summary, "Summary", "Snapshots must not mutate retrospectively")
    }

    func testUnavailableArchiveDoesNotPublishOrRunDestructiveOwners() {
        let repository = ConversationRepository(archive: nil, initialError: "Storage unavailable")
        XCTAssertEqual(repository.errorText, "Storage unavailable")
        repository.recordsChanged = { _, _ in XCTFail("No successful archive mutation") }
        repository.dataOwners = [ConversationDataOwner("must not erase") { _ in XCTFail("Archive unavailable") }]
        XCTAssertFalse(repository.add(record("one")))
        XCTAssertFalse(repository.clear())
        XCTAssertEqual(repository.all(), [])
        XCTAssertNil(repository.completeIDs())
        XCTAssertFalse(repository.contains("one"))
        XCTAssertNotNil(repository.errorText)
    }

    func testDamagedRecordWarningStaysUntilDismissedAndGoodHistoryRemains() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root)
        try archive.save(record("good"))
        try Data("broken json".utf8).write(to: root.appendingPathComponent("broken.json"))
        let repository = ConversationRepository(archive: archive)
        XCTAssertNil(repository.completeIDs(), "A damaged archive is never treated as empty")
        // completeIDs quarantined it; add a second damaged record to exercise the displayed warning.
        try Data("broken json".utf8).write(to: root.appendingPathComponent("broken-again.json"))
        XCTAssertEqual(repository.all().map(\.id), ["good"])
        XCTAssertNotNil(repository.archiveWarning)
        _ = repository.all()
        XCTAssertNotNil(repository.archiveWarning)
        repository.dismissArchiveWarning()
        XCTAssertNil(repository.archiveWarning)
    }
}
