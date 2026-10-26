import XCTest
@testable import ListenToMeCore

@MainActor
final class ConversationPersistenceCoordinatorTests: XCTestCase {
    private let bytes = Data("Current conversation".utf8)
    private struct WriteFailure: Error {}

    func testUnchangedDataSkipsEveryWrite() throws {
        let coordinator = ConversationPersistenceCoordinator()
        var archive: [Data] = [], exports: [Data] = [], snapshots: [Data] = []
        for _ in 0..<2 {
            try coordinator.save(bytes, hasContent: true, wasArchived: false,
                                 archive: { archive.append(self.bytes) }, archived: { exports.append(self.bytes) },
                                 activeSnapshot: { snapshots.append(self.bytes) })
        }
        XCTAssertEqual(archive, [bytes])
        XCTAssertEqual(exports, [bytes])
        XCTAssertEqual(snapshots, [bytes])
    }

    func testEmptyPreviouslyArchivedConversationStillUpdatesHistory() throws {
        let coordinator = ConversationPersistenceCoordinator()
        let empty = Data("Empty edit".utf8)
        var history = bytes, active = bytes
        try coordinator.save(empty, hasContent: false, wasArchived: true,
                             archive: { history = empty }, archived: {}, activeSnapshot: { active = empty })
        XCTAssertEqual(history, empty, "Clearing the final text must not leave old History content")
        XCTAssertEqual(active, empty)
    }

    func testNewEmptyConversationWritesOnlyActiveSnapshot() throws {
        let coordinator = ConversationPersistenceCoordinator()
        var active: Data?
        try coordinator.save(bytes, hasContent: false, wasArchived: false,
                             archive: { XCTFail("An untouched empty conversation does not belong in History") },
                             archived: { XCTFail("No archive means no export") }, activeSnapshot: { active = self.bytes })
        XCTAssertEqual(active, bytes)
    }

    func testArchiveFailureHasNoDownstreamEffectsAndCanRetry() throws {
        let coordinator = ConversationPersistenceCoordinator()
        var fail = true, history: Data?, active: Data?, exported: Data?
        func save() throws {
            try coordinator.save(bytes, hasContent: true, wasArchived: false, archive: {
                if fail { throw WriteFailure() }; history = bytes
            }, archived: { exported = bytes }, activeSnapshot: { active = bytes })
        }
        XCTAssertThrowsError(try save())
        XCTAssertNil(history)
        XCTAssertNil(exported)
        XCTAssertNil(active)
        fail = false
        try save()
        XCTAssertEqual(history, bytes)
        XCTAssertEqual(exported, bytes)
        XCTAssertEqual(active, bytes)
    }

    func testActiveSnapshotFailureDoesNotAcknowledgeAndRetryWritesBothCopies() throws {
        let coordinator = ConversationPersistenceCoordinator()
        var fail = true, history: Data?, active: Data?, exports = 0, archiveWrites = 0
        var order: [String] = []
        func save() throws {
            try coordinator.save(bytes, hasContent: true, wasArchived: false, archive: {
                order.append("archive"); history = bytes; archiveWrites += 1
            }, archived: { order.append("export"); exports += 1 }, activeSnapshot: {
                order.append("active")
                if fail { throw WriteFailure() }; active = bytes
            })
        }
        XCTAssertThrowsError(try save())
        XCTAssertEqual(history, bytes)
        XCTAssertNil(active)
        fail = false
        history = Data("Storage repaired".utf8)
        try save()
        XCTAssertEqual(history, bytes, "The same bytes must be written again after a partial failure")
        XCTAssertEqual(active, bytes)
        XCTAssertEqual(archiveWrites, 2)
        XCTAssertEqual(exports, 2)
        XCTAssertEqual(order, ["archive", "export", "active", "archive", "export", "active"])
    }

    func testInvalidationForcesAWriteAfterConversationChanges() throws {
        let coordinator = ConversationPersistenceCoordinator()
        var snapshots = 0
        func save() throws {
            try coordinator.save(bytes, hasContent: false, wasArchived: false, archive: {}, archived: {},
                                 activeSnapshot: { snapshots += 1 })
        }
        try save()
        coordinator.invalidate()
        try save()
        XCTAssertEqual(snapshots, 2)
    }
}
