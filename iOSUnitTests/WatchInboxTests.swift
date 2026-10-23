import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// The iPhone's receive path for Apple Watch audio (issue #181). It runs on the WatchConnectivity
/// delegate queue and may wake the app in the background, so it only files bytes.
final class WatchInboxTests: XCTestCase {
    private var root: URL!
    private var scratch: URL!
    private let id = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private var savedBackupSetting: Any?

    override func setUp() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("WatchInbox")
        scratch = base.appendingPathComponent("Delivered")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        savedBackupSetting = UserDefaults.standard.object(forKey: MobileSession.excludeBackupKey)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        UserDefaults.standard.set(savedBackupSetting, forKey: MobileSession.excludeBackupKey)
    }

    private func delivered(bytes: Int = 64) throws -> URL {
        let url = scratch.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func metadata(_ index: Int, isLast: Bool = false) -> [String: Any] {
        WatchChunkMetadata(recordingID: id, index: index, startOffset: TimeInterval(index) * 300, duration: 300,
                           isLast: isLast, startedAt: startedAt, watchBuild: "28").transferMetadata
    }

    func testAcceptMovesTheFileSynchronously() throws {
        let inbox = WatchInbox(root: root)
        let source = try delivered()
        XCTAssertEqual(inbox.accept(fileAt: source, metadata: metadata(0), now: startedAt), .stored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "Moved before accept returns")
        let stored = root.appendingPathComponent(id.uuidString).appendingPathComponent("0.m4a")
        XCTAssertEqual(inbox.chunkURL(recordingID: id, index: 0), stored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        let ledgers = inbox.ledgers()
        XCTAssertEqual(ledgers.count, 1)
        XCTAssertEqual(ledgers.first?.recordingID, id)
        XCTAssertEqual(ledgers.first?.startedAt, startedAt)
        XCTAssertEqual(ledgers.first?.chunks.map(\.index), [0])
    }

    func testDuplicateDeliveryIsANoOp() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(bytes: 10), metadata: metadata(0), now: startedAt), .stored)
        let again = try delivered(bytes: 20)
        XCTAssertEqual(inbox.accept(fileAt: again, metadata: metadata(0), now: startedAt), .duplicate)
        let stored = inbox.chunkURL(recordingID: id, index: 0)
        XCTAssertEqual(try Data(contentsOf: stored).count, 10, "The first delivery is kept")
        XCTAssertEqual(inbox.ledgers().first?.chunks.count, 1)
    }

    func testOversizedFileOrBadMetadataIsRejectedAndNothingStored() throws {
        let inbox = WatchInbox(root: root)
        let large = try delivered(bytes: WatchChunkMetadata.maximumFileBytes + 1)
        guard case .rejected = inbox.accept(fileAt: large, metadata: metadata(0), now: startedAt) else {
            return XCTFail("An oversized file must be rejected")
        }
        var future = metadata(0)
        future["v"] = 2
        guard case .rejected = inbox.accept(fileAt: try delivered(), metadata: future, now: startedAt) else {
            return XCTFail("Another protocol version must be rejected")
        }
        var bad = metadata(0)
        bad["index"] = 1_000
        guard case .rejected = inbox.accept(fileAt: try delivered(), metadata: bad, now: startedAt) else {
            return XCTFail("An out-of-range index must be rejected")
        }
        guard case .rejected = inbox.accept(fileAt: scratch.appendingPathComponent("missing.m4a"), metadata: metadata(0),
                                            now: startedAt) else { return XCTFail("A missing file must be rejected") }
        XCTAssertTrue(inbox.ledgers().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString).path))
    }

    func testStoredNameNeverComesFromMetadata() throws {
        let inbox = WatchInbox(root: root)
        var hostile = metadata(2)
        hostile["path"] = "../../Escape.m4a"
        hostile["name"] = "../Conversations/x.json"
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: hostile, now: startedAt), .stored)
        let folder = root.appendingPathComponent(id.uuidString)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["2.json", "2.m4a", "manifest.json"], "Named from the parsed index only")
        let everything = try FileManager.default.contentsOfDirectory(atPath: root.deletingLastPathComponent().path)
        XCTAssertEqual(Set(everything), ["WatchInbox", "Delivered"])
    }

    func testEndMarkerBeforeAnyChunkCreatesTheLedger() throws {
        let inbox = WatchInbox(root: root)
        let end = WatchRecordingEnd(recordingID: id, startedAt: startedAt, lastIndex: 1, unexpected: true)
        inbox.acceptEnd(userInfo: end.userInfo, now: startedAt)
        inbox.acceptEnd(userInfo: ["v": 2, "end": id.uuidString], now: startedAt)
        let ledger = try XCTUnwrap(inbox.ledgers().first)
        XCTAssertEqual(ledger.lastIndex, 1)
        XCTAssertTrue(ledger.endedUnexpectedly)
        XCTAssertTrue(ledger.chunks.isEmpty)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        XCTAssertEqual(inbox.ledgers().first?.chunks.map(\.index), [0])
        XCTAssertEqual(inbox.ledgers().first?.lastIndex, 1)
    }

    /// Raw watch audio is transient and promised to stay on this iPhone: it is kept out of iCloud
    /// Backup whatever the conversations' backup setting says.
    func testInboxIsAlwaysExcludedFromBackup() throws {
        let inbox = WatchInbox(root: root)
        UserDefaults.standard.set(false, forKey: MobileSession.excludeBackupKey)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let folder = root.appendingPathComponent(id.uuidString)
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(folder))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(root))
        try PrivateStorage.setExcludedFromBackup(false, at: root)
        inbox.applyBackupExclusion()
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(root))
    }

    @MainActor
    func testSessionBackupToggleNeverPutsWatchAudioInTheBackup() throws {
        let storage = root.deletingLastPathComponent().appendingPathComponent("Session")
        let inbox = WatchInbox(root: storage.appendingPathComponent("WatchInbox"))
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let folder = inbox.root.appendingPathComponent(id.uuidString)
        let session = MobileSession(storageDirectory: storage, makeRecorder: { LifecycleTestRecorder() })
        session.excludeFromBackup = true
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(folder))
        session.excludeFromBackup = false
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(folder))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(inbox.root))
    }

    func testStoredChunkUsesTheArchiveProtectionClass() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let attributes = try FileManager.default.attributesOfItem(atPath: inbox.chunkURL(recordingID: id, index: 0).path)
        let expected = try XCTUnwrap(PrivateStorage.directoryAttributes[.protectionKey] as? FileProtectionType)
        XCTAssertEqual(WatchInbox.chunkAttributes[.protectionKey] as? FileProtectionType, expected)
        #if targetEnvironment(simulator)
        // The simulator has no data protection and reports no class; a device reads it back.
        _ = attributes
        #else
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, expected)
        #endif
    }

    func testDeleteChunksAndRemoveRecording() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(1, isLast: true), now: startedAt), .stored)
        inbox.deleteChunks([0], of: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.chunkURL(recordingID: id, index: 0).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.chunkURL(recordingID: id, index: 1).path))
        var ledger = try XCTUnwrap(inbox.ledgers().first)
        ledger.markFailed("x")
        try inbox.save(ledger)
        XCTAssertEqual(inbox.ledgers().first?.failure, "x")
        try inbox.removeRecording(id)
        XCTAssertTrue(inbox.ledgers().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString).path))
        try inbox.removeRecording(id)
    }

    func testUnreadableManifestIsSkippedAndLedgersAreOrderedByStart() throws {
        let inbox = WatchInbox(root: root)
        let later = UUID()
        let laterMetadata = WatchChunkMetadata(recordingID: later, index: 0, startOffset: 0, duration: 300, isLast: false,
                                               startedAt: startedAt.addingTimeInterval(60), watchBuild: "28")
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: laterMetadata.transferMetadata, now: startedAt),
                       .stored)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let broken = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: broken.appendingPathComponent("manifest.json"))
        XCTAssertEqual(inbox.ledgers().map(\.recordingID), [id, later])
    }

    func testUpdateReadsTheLatestManifest() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let stale = try XCTUnwrap(inbox.ledgers().first)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(1), now: startedAt), .stored)
        // A drain holding an older copy must not drop the chunk that arrived meanwhile.
        let covered = try inbox.update(stale.recordingID) { $0.markTranscribed(through: 300) }
        XCTAssertEqual(covered, [0])
        XCTAssertEqual(inbox.ledgers().first?.chunks.map(\.index), [0, 1])
        XCTAssertNil(try inbox.update(UUID()) { $0.markTranscribed(through: 1) })
        XCTAssertFalse(try inbox.completeRecording(UUID(), now: startedAt))
    }

    // MARK: Storage failures never lose delivered audio

    private struct DiskFull: Error {}

    /// A writer that fails for the files whose names `failing` accepts, like a full disk.
    private func inbox(failing: @escaping @Sendable (String) -> Bool) -> WatchInbox {
        WatchInbox(root: root, writeFile: { data, url in
            if failing(url.lastPathComponent) { throw DiskFull() }
            try data.write(to: url, options: PrivateStorage.writingOptions)
        })
    }

    func testManifestWriteFailureKeepsTheAudioAndTheNextDrainAdoptsIt() throws {
        let failing = inbox(failing: { $0 == "manifest.json" })
        let metadata = WatchChunkMetadata(recordingID: id, index: 2, startOffset: 660, duration: 120, isLast: true,
                                          startedAt: startedAt, watchBuild: "28")
        XCTAssertEqual(failing.accept(fileAt: try delivered(), metadata: metadata.transferMetadata, now: startedAt),
                       .stored, "The audio is on disk; only its index is missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: failing.chunkURL(recordingID: id, index: 2).path))
        XCTAssertTrue(failing.ledgers().isEmpty)

        let healthy = WatchInbox(root: root)
        healthy.tidy(now: startedAt.addingTimeInterval(60))
        let ledger = try XCTUnwrap(healthy.ledgers().first)
        XCTAssertEqual(ledger.startedAt, startedAt)
        XCTAssertEqual(ledger.chunks.map(\.index), [2])
        XCTAssertEqual(ledger.chunks.first?.startOffset, 660, "Read from the chunk's own metadata file")
        XCTAssertEqual(ledger.lastIndex, 2)
    }

    func testAudioWithNoMetadataAtAllIsStillAdopted() throws {
        let failing = inbox(failing: { _ in true })
        XCTAssertEqual(failing.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        XCTAssertEqual(failing.accept(fileAt: try delivered(), metadata: metadata(1), now: startedAt), .stored)
        let healthy = WatchInbox(root: root)
        healthy.tidy(now: startedAt)
        let ledger = try XCTUnwrap(healthy.ledgers().first)
        XCTAssertEqual(ledger.chunks.map(\.index), [0, 1])
        XCTAssertEqual(ledger.chunks[1].startOffset, ledger.chunks[0].end, "Placed after the chunk before it")
    }

    func testUnreadableManifestIsSetAsideNotOverwritten() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let folder = root.appendingPathComponent(id.uuidString)
        try Data("{".utf8).write(to: folder.appendingPathComponent("manifest.json"))

        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(1), now: startedAt), .stored)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("manifest.json.corrupt-") }, "\(names)")
        XCTAssertEqual(inbox.ledgers().first?.chunks.map(\.index), [1])
        inbox.tidy(now: startedAt)
        XCTAssertEqual(inbox.ledgers().first?.chunks.map(\.index), [0, 1], "Chunk 0's audio is picked up again")
    }

    func testRefusedAudioIsRecordedForHistory() throws {
        let inbox = WatchInbox(root: root)
        inbox.clearProblems()
        let large = try delivered(bytes: WatchChunkMetadata.maximumFileBytes + 1)
        guard case .rejected = inbox.accept(fileAt: large, metadata: metadata(0), now: startedAt) else {
            return XCTFail("An oversized file must be rejected")
        }
        XCTAssertEqual(inbox.problems().count, 1)
        XCTAssertTrue(inbox.problems().first?.contains("too large") == true, "\(inbox.problems())")
        XCTAssertTrue(WatchInbox(root: root).problems() == inbox.problems(), "Kept across launches")
        inbox.clearProblems()
        XCTAssertTrue(inbox.problems().isEmpty)
    }

    func testCompletedRecordingIsKeptAsATombstoneThenPruned() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0, isLast: true), now: startedAt),
                       .stored)
        _ = try inbox.update(id) { $0.markTranscribed(through: 300) }
        inbox.deleteChunks([0], of: id)
        XCTAssertTrue(try inbox.completeRecording(id, now: startedAt))
        XCTAssertEqual(inbox.ledgers().first?.completed, true)
        XCTAssertFalse(try inbox.completeRecording(id, now: startedAt), "Already complete")
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .duplicate,
                       "The watch sending the chunk again is recognized")
        inbox.tidy(now: startedAt.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(inbox.ledgers().count, 1)
        inbox.tidy(now: startedAt.addingTimeInterval(8 * 86_400))
        XCTAssertTrue(inbox.ledgers().isEmpty, "A week later the tombstone goes")
    }
}

/// Review follow-ups from #190 (#191): the completion sweep, refusal wording and a deleted
/// recording's tombstone.
extension WatchInboxTests {
    /// A chunk filed while its manifest could not be written is adopted, never swept away, when the
    /// recording completes.
    func testCompletingARecordingAdoptsAChunkMissingFromTheManifest() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0, isLast: true), now: startedAt),
                       .stored)
        let failing = WatchInbox(root: root, writeFile: { data, url in
            if url.lastPathComponent == "manifest.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: PrivateStorage.writingOptions)
        })
        // Continue after an interruption: chunk 1 arrives, but its manifest entry is never written.
        XCTAssertEqual(failing.accept(fileAt: try delivered(), metadata: metadata(1), now: startedAt), .stored)
        _ = try inbox.update(id) { $0.markTranscribed(through: 300) }
        inbox.deleteChunks([0], of: id)

        XCTAssertFalse(try inbox.completeRecording(id, now: startedAt), "Chunk 1 still needs its text")
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.chunkURL(recordingID: id, index: 1).path))
        XCTAssertEqual(inbox.ledgers().first?.chunks.map(\.index), [0, 1])
    }

    /// The watch deletes a part once it is delivered, so a refusal never promises it is sent again,
    /// and never shows Swift error text.
    func testRefusalsSayThePartIsMissingInPlainWords() throws {
        let inbox = WatchInbox(root: root)
        inbox.clearProblems()
        defer { inbox.clearProblems() }
        var bad = metadata(0)
        bad["index"] = 1_000
        _ = inbox.accept(fileAt: try delivered(), metadata: bad, now: startedAt)
        var future = metadata(0)
        future["v"] = 2
        _ = inbox.accept(fileAt: try delivered(), metadata: future, now: startedAt)
        // A file where the inbox folder should be: nothing can be stored.
        try Data().write(to: root)
        guard case .rejected = inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt) else {
            return XCTFail("Storage failure must refuse")
        }
        let problems = inbox.problems()
        XCTAssertEqual(problems.count, 3)
        XCTAssertEqual(problems[0], "An Apple Watch recording part could not be read, so it is missing from "
            + "the recording.")
        XCTAssertEqual(problems[1], "An Apple Watch recording part came from another version of ListenToMe, so "
            + "it is missing from the recording. Update ListenToMe on your iPhone and Apple Watch.")
        XCTAssertTrue(problems[2].hasPrefix("An Apple Watch recording part could not be stored on this iPhone"))
        XCTAssertTrue(problems[2].contains("so it is missing from the recording"))
        for problem in problems {
            XCTAssertFalse(problem.contains("sent again"), problem)
            XCTAssertFalse(problem.contains("malformed"), problem)
            XCTAssertFalse(problem.contains("unsupportedVersion"), problem)
        }
    }

    /// A deleted watch conversation leaves a tombstone, so the watch sending an old part again does
    /// not bring it back as a new conversation. The tombstone goes after `tombstoneLifetime`.
    func testADeletedRecordingDiscardsLateDeliveriesUntilItsTombstoneExpires() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        try inbox.removeRecording(id, tombstoneAt: startedAt)
        XCTAssertTrue(inbox.ledgers().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.chunkURL(recordingID: id, index: 0).path))

        let later = startedAt.addingTimeInterval(86_400)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: later), .discarded)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(1, isLast: true), now: later),
                       .discarded)
        let end = WatchRecordingEnd(recordingID: id, startedAt: startedAt, lastIndex: 1, unexpected: true)
        inbox.acceptEnd(userInfo: end.userInfo, now: later)
        inbox.tidy(now: later)
        XCTAssertTrue(inbox.ledgers().isEmpty, "Nothing is filed for a deleted recording")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.chunkURL(recordingID: id, index: 1).path))

        inbox.tidy(now: startedAt.addingTimeInterval(8 * 86_400))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString).path))
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0),
                                    now: startedAt.addingTimeInterval(8 * 86_400)), .stored)
    }

    /// Deleting only the audio (History's Delete on a waiting row) leaves no tombstone: the
    /// conversation stays, and a later Continue part reopens it.
    func testRemovingOnlyTheAudioLeavesNoTombstone() throws {
        let inbox = WatchInbox(root: root)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        try inbox.removeRecording(id)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(1), now: startedAt), .stored)
    }

    /// The audio is gone once the folder is removed; a tombstone that cannot be written is only logged,
    /// so the user is not told the audio could not be deleted.
    func testATombstoneWriteFailureDoesNotFailTheDelete() throws {
        XCTAssertEqual(WatchInbox(root: root).accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt),
                       .stored)
        let failing = WatchInbox(root: root, writeFile: { data, url in
            if url.lastPathComponent == "deleted" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: PrivateStorage.writingOptions)
        })
        XCTAssertNoThrow(try failing.removeRecording(id, tombstoneAt: startedAt))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failing.chunkURL(recordingID: id, index: 0).path))
        XCTAssertTrue(failing.ledgers().isEmpty)
    }
}
