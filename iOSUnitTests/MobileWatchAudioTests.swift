import AVFoundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

@MainActor
final class MobileWatchAudioTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private let recording = UUID()

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func session(_ fake: FakeWatchTranscriber, enabled: Bool) -> MobileSession {
        let saved = MobileSavedAudio(root: root.appendingPathComponent("SavedAudio"), defaults: defaults)
        saved.enabled = enabled
        let session = MobileSession(storageDirectory: root, makeWatchTranscriber: { fake }, savedAudio: saved)
        session.applicationIsActive = { true }
        return session
    }

    private func deliver(_ session: MobileSession, index: Int = 0, offset: Double = 0,
                         last: Bool = true) throws {
        let url = root.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
        buffer.frameLength = 32_000
        for i in 0..<32_000 { buffer.floatChannelData![0][i] = 0.1 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let metadata = WatchChunkMetadata(recordingID: recording, index: index, startOffset: offset,
            duration: 2, isLast: last, startedAt: Date(), watchBuild: "test")
        XCTAssertEqual(session.watchInbox.accept(fileAt: url, metadata: metadata.transferMetadata, now: Date()), .stored)
    }

    private func drain(_ session: MobileSession) async {
        session.importWatchInbox()
        await session.watchDrainTask?.value
    }

    private func record(_ session: MobileSession) throws -> SessionRecord {
        try XCTUnwrap(session.history.first { $0.sourceImportID == MobileSession.watchSourceID(recording) })
    }

    func testOptInRetainsPlayableAudioAndOffDeletesOnlyInboxCopy() async throws {
        for enabled in [false, true] {
            let fake = FakeWatchTranscriber()
            fake.script = [0: [.init(text: "Hello Watch", start: 0, end: 2)]]
            let session = session(fake, enabled: enabled)
            try deliver(session)
            await drain(session)
            let record = try record(session)
            XCTAssertEqual(record.segments?.count, 1)
            let runs = session.savedAudio.runs(for: record.id)
            XCTAssertEqual(runs.count, enabled ? 1 : 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                session.watchInbox.chunkURL(recordingID: recording, index: 0).path))
            if let run = runs.first {
                let file = try AVAudioFile(forReading: XCTUnwrap(session.savedAudio.library.url(
                    for: run, conversationID: record.id)))
                XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 2, accuracy: 0.001)
                XCTAssertEqual(run.deviceName, "Apple Watch")
            }
            try FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    func testRetryDoesNotDuplicateOrResurrectDeletedAudioAndKeepsOverlapTimeline() async throws {
        let fake = FakeWatchTranscriber()
        fake.failBefore = (0, CocoaError(.fileReadUnknown))
        let session = session(fake, enabled: true)
        try deliver(session, last: false)
        try deliver(session, index: 1, offset: 1)
        await drain(session)
        let record = try record(session)
        XCTAssertEqual(session.savedAudio.runs(for: record.id).map(\.timelineOffset), [0, 2])
        session.savedAudio.deleteAll()
        fake.failBefore = nil
        fake.script = [0: [.init(text: "First", start: 0, end: 2)],
                       1: [.init(text: "Second", start: 2, end: 4)]]
        session.retryWatchRecording(recording)
        await session.watchDrainTask?.value
        XCTAssertTrue(session.savedAudio.runs(for: record.id).isEmpty)
        XCTAssertEqual(try self.record(session).segments?.count, 2)
    }

    func testPartialRetryKeepsPersistedOffsetsAfterEarlierChunkWasDeleted() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [.init(text: "First", start: 0, end: 2)],
                       1: [.init(text: "Second", start: 2, end: 4)]]
        fake.failAfter = (0, CocoaError(.fileReadUnknown))
        let session = session(fake, enabled: true)
        try deliver(session, last: false)
        try deliver(session, index: 1, offset: 1)
        await drain(session)
        XCTAssertEqual(fake.offsets, [[0, 2]])
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            session.watchInbox.chunkURL(recordingID: recording, index: 0).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            session.watchInbox.chunkURL(recordingID: recording, index: 1).path))
        fake.failAfter = nil
        // Relaunch reconstructs placement from the persisted inbox, even if saving is now off.
        let relaunched = self.session(fake, enabled: false)
        relaunched.retryWatchRecording(recording)
        await relaunched.watchDrainTask?.value
        XCTAssertEqual(fake.offsets, [[0, 2], [2]])
        let record = try self.record(relaunched)
        XCTAssertEqual(record.segments?.map(\.text), ["First", "Second"])
        let runs = relaunched.savedAudio.runs(for: record.id)
        XCTAssertEqual(runs.map(\.timelineOffset), [0, 2])
        let last = try XCTUnwrap(record.segments?.last)
        XCTAssertEqual(SavedAudioSeek.target(for: last, index: 1, in: runs)?.time, 0)
    }

    func testContinueAfterInboxDeletionRetainsNewPartWithoutWaitingForMissingParts() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [.init(text: "Before", start: 0, end: 2)],
                       2: [.init(text: "After", start: 4, end: 6)]]
        let session = session(fake, enabled: true)
        try deliver(session)
        await drain(session)
        let id = try record(session).id
        session.deleteWatchRecording(recording)
        try deliver(session, index: 2, offset: 4)
        await drain(session)
        XCTAssertEqual(try record(session).segments?.map(\.text), ["Before", "After"])
        XCTAssertEqual(try record(session).isComplete, true)
        XCTAssertEqual(session.savedAudio.runs(for: id).map(\.timelineOffset), [0, 4])
    }

    func testStorageFailureKeepsInboxThenRetryCommitsOneCopyBeforeDeletingIt() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [.init(text: "Saved once", start: 0, end: 2)]]
        let session = session(fake, enabled: true)
        try deliver(session)
        let audioRoot = session.savedAudio.library.root
        try Data([1]).write(to: audioRoot)
        await drain(session)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            session.watchInbox.chunkURL(recordingID: recording, index: 0).path))
        try FileManager.default.removeItem(at: audioRoot)
        session.retryWatchRecording(recording)
        await session.watchDrainTask?.value
        let record = try record(session)
        XCTAssertEqual(record.segments?.count, 1)
        XCTAssertEqual(session.savedAudio.runs(for: record.id).count, 1)
        let relaunched = self.session(FakeWatchTranscriber(), enabled: true)
        await drain(relaunched)
        XCTAssertEqual(relaunched.savedAudio.runs(for: record.id).count, 1)
        XCTAssertEqual(try self.record(relaunched).segments?.count, 1)
        session.savedAudio.delete(conversation: record.id)
        XCTAssertTrue(session.savedAudio.runs(for: record.id).isEmpty)
    }
}
