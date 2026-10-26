import XCTest
@testable import ListenToMeCore

@MainActor
final class ConversationCheckpointCoordinatorTests: XCTestCase {
    private func key(_ revision: Int = 1, complete: Bool = false) -> SessionCheckpointKey {
        SessionCheckpointKey(revision: revision, title: "Meeting", summary: "", notes: "",
                             quickSuggestion: "", deepAnswer: "", complete: complete)
    }

    private func record(_ date: Date) -> SessionRecord {
        SessionRecord(id: "meeting", title: "Meeting", date: date, transcript: "Final speech", summary: "")
    }

    func testDisabledOrEmptyCheckpointDoesNotReadOrBuildContent() {
        let coordinator = ConversationCheckpointCoordinator()
        for (allowed, content) in [(false, true), (false, false), (true, false)] {
            let result = coordinator.checkpoint(allowed: allowed, hasContent: content,
                now: { XCTFail("No date needed"); return Date() },
                makeKey: { XCTFail("No content read allowed"); return self.key() },
                makeRecord: { XCTFail("No transcript assembly allowed"); return self.record($0) },
                persist: { _ in XCTFail("No persistence allowed"); return true })
            switch result {
            case .disabled: XCTAssertFalse(allowed)
            case .empty: XCTAssertTrue(allowed); XCTAssertFalse(content)
            default: XCTFail("Unexpected checkpoint result")
            }
        }
        XCTAssertNil(coordinator.startedAt)
    }

    func testFailedWriteRetriesSameKeyAndOnlySuccessfulWritePinsDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // A file where the archive directory belongs makes the real archive write fail.
        try Data("blocked".utf8).write(to: root)
        let repository = ConversationRepository(archive: SessionArchive(directory: root))
        let coordinator = ConversationCheckpointCoordinator()
        let first = Date(timeIntervalSince1970: 100), retry = Date(timeIntervalSince1970: 200)
        func save(at date: Date) -> ConversationCheckpointCoordinator.Outcome {
            coordinator.checkpoint(allowed: true, hasContent: true, now: { date },
                makeKey: { self.key() }, makeRecord: self.record, persist: repository.add)
        }
        guard case .failed = save(at: first) else { return XCTFail("Write must fail") }
        XCTAssertNil(coordinator.startedAt)
        try FileManager.default.removeItem(at: root)
        guard case .saved(let saved) = save(at: retry) else { return XCTFail("Same key must retry") }
        XCTAssertEqual(saved.date, retry)
        XCTAssertEqual(coordinator.startedAt, retry)
        XCTAssertEqual(repository.all().first?.date, retry)
        guard case .unchanged = save(at: first) else { return XCTFail("Successful write acknowledges key") }
    }

    func testUnchangedSkipsAssemblyButCompletionAndForcePersistWithOriginalDate() {
        let coordinator = ConversationCheckpointCoordinator()
        let first = Date(timeIntervalSince1970: 100)
        var builds = 0, writes = 0
        func save(complete: Bool = false, force: Bool = false) -> ConversationCheckpointCoordinator.Outcome {
            coordinator.checkpoint(allowed: true, hasContent: true, force: force,
                now: { first.addingTimeInterval(Double(writes)) },
                makeKey: { self.key(complete: complete) },
                makeRecord: { builds += 1; return self.record($0) },
                persist: { record in writes += 1; XCTAssertEqual(record.date, first); return true })
        }
        guard case .saved = save() else { return XCTFail("Initial save") }
        guard case .unchanged = save() else { return XCTFail("Idle timer") }
        XCTAssertEqual(builds, 1); XCTAssertEqual(writes, 1)
        guard case .saved = save(complete: true) else { return XCTFail("Stop changes completion") }
        guard case .saved = save(complete: true, force: true) else { return XCTFail("Explicit retry forces save") }
        XCTAssertEqual(builds, 3); XCTAssertEqual(writes, 3)
    }

    func testFailedUpdateDoesNotAcknowledgeNewContentOrChangeExistingStart() {
        let coordinator = ConversationCheckpointCoordinator()
        let start = Date(timeIntervalSince1970: 100)
        coordinator.reset(startedAt: start)
        var writes = 0
        func save(_ revision: Int, succeeds: Bool) -> ConversationCheckpointCoordinator.Outcome {
            coordinator.checkpoint(allowed: true, hasContent: true,
                now: { XCTFail("Restored date is pinned"); return Date() },
                makeKey: { self.key(revision) }, makeRecord: self.record,
                persist: { record in writes += 1; XCTAssertEqual(record.date, start); return succeeds })
        }
        guard case .saved = save(1, succeeds: true) else { return XCTFail("Initial save") }
        guard case .failed = save(2, succeeds: false) else { return XCTFail("Failed update") }
        guard case .saved = save(2, succeeds: true) else { return XCTFail("Retry changed content") }
        XCTAssertEqual(writes, 3)
        XCTAssertEqual(coordinator.startedAt, start)
    }

    func testResetDropsDirtyMarkerAndPreservesReopenedDateWithoutBypassingPrivacy() {
        let coordinator = ConversationCheckpointCoordinator()
        let reopened = Date(timeIntervalSince1970: 50)
        var writes = 0
        func save(allowed: Bool = true) -> ConversationCheckpointCoordinator.Outcome {
            coordinator.checkpoint(allowed: allowed, hasContent: true, makeKey: { self.key() },
                makeRecord: self.record, persist: { _ in writes += 1; return true })
        }
        guard case .saved = save() else { return XCTFail("Initial save") }
        coordinator.reset()
        XCTAssertNil(coordinator.startedAt)
        guard case .disabled = save(allowed: false) else { return XCTFail("Deleted content stays disabled") }
        XCTAssertEqual(writes, 1)
        coordinator.reset(startedAt: reopened)
        guard case .saved(let saved) = save() else { return XCTFail("Identical new identity must save") }
        XCTAssertEqual(saved.date, reopened)
        XCTAssertEqual(writes, 2)
    }
}
