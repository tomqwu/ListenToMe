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
        XCTAssertEqual(names, ["2.m4a", "manifest.json"])
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

    func testInboxFollowsTheBackupExclusionSetting() throws {
        let inbox = WatchInbox(root: root)
        UserDefaults.standard.set(true, forKey: MobileSession.excludeBackupKey)
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let folder = root.appendingPathComponent(id.uuidString)
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(folder))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(root))
        inbox.applyBackupExclusion(false)
        XCTAssertFalse(PrivateStorage.isExcludedFromBackup(folder))
        XCTAssertFalse(PrivateStorage.isExcludedFromBackup(root))
        inbox.applyBackupExclusion(true)
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(folder))
    }

    @MainActor
    func testSessionBackupToggleReachesTheWatchInbox() throws {
        let storage = root.deletingLastPathComponent().appendingPathComponent("Session")
        let inbox = WatchInbox(root: storage.appendingPathComponent("WatchInbox"))
        XCTAssertEqual(inbox.accept(fileAt: try delivered(), metadata: metadata(0), now: startedAt), .stored)
        let folder = inbox.root.appendingPathComponent(id.uuidString)
        let session = MobileSession(storageDirectory: storage, makeRecorder: { LifecycleTestRecorder() })
        session.excludeFromBackup = true
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(folder))
        session.excludeFromBackup = false
        XCTAssertFalse(PrivateStorage.isExcludedFromBackup(folder))
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
    }
}
