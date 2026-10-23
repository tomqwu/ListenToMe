import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// Apple Watch recordings become conversations in the foreground (issue #181).
@MainActor
final class MobileWatchDrainTests: XCTestCase {
    private var root: URL!
    private var savedLanguage: Any?
    private let recordingID = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let hour: TimeInterval = 3_600

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        savedLanguage = UserDefaults.standard.object(forKey: MobileSession.languageKey)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.set(savedLanguage, forKey: MobileSession.languageKey)
    }

    // MARK: Helpers

    private func makeSession(_ transcriber: FakeWatchTranscriber,
                             recorder: (any MobileRecording)? = nil) -> MobileSession {
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder ?? LifecycleTestRecorder() },
                                    makeWatchTranscriber: { transcriber })
        session.applicationIsActive = { true }
        return session
    }

    private func line(_ text: String, chunk: Int) -> FakeWatchTranscriber.Line {
        // Ends at the chunk's end, so the line covers the chunk wholly.
        FakeWatchTranscriber.Line(text: text, start: TimeInterval(chunk) * 300 + 10, end: TimeInterval(chunk + 1) * 300)
    }

    /// Delivers chunk `index` (300 s each) as if WatchConnectivity handed it over at `at`.
    private func deliver(_ session: MobileSession, _ index: Int, isLast: Bool = false, at: Date? = nil) throws {
        let source = root.appendingPathComponent("delivery-\(UUID().uuidString).m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: source)
        let metadata = WatchChunkMetadata(recordingID: recordingID, index: index, startOffset: TimeInterval(index) * 300,
                                          duration: 300, isLast: isLast, startedAt: startedAt, watchBuild: "28")
        XCTAssertEqual(session.watchInbox.accept(fileAt: source, metadata: metadata.transferMetadata, now: at ?? startedAt),
                       .stored)
    }

    private func drain(_ session: MobileSession, now: Date? = nil) async {
        session.importWatchInbox(now: now ?? startedAt.addingTimeInterval(60))
        await session.watchDrainTask?.value
    }

    private func watchRecords(_ session: MobileSession) -> [SessionRecord] {
        session.history.filter { $0.sourceImportID == "watch:\(recordingID.uuidString)" }
    }

    private func archived() throws -> [SessionRecord] {
        try SessionArchive(directory: root.appendingPathComponent("Conversations")).all()
            .filter { $0.sourceImportID == "watch:\(recordingID.uuidString)" }
    }

    private func chunkExists(_ session: MobileSession, _ index: Int) -> Bool {
        FileManager.default.fileExists(atPath: session.watchInbox.chunkURL(recordingID: recordingID, index: index).path)
    }

    // MARK: Tests

    func testDrainCreatesAConversationInHistoryWithoutSwitchingTheOpenOne() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("The budget review moves to Friday.", chunk: 0)],
                       1: [line("Sarah will send the numbers.", chunk: 1)]]
        let session = makeSession(fake)
        session.notes = "My own meeting"
        XCTAssertTrue(session.save(announce: false))
        let openID = session.id
        try deliver(session, 0)
        try deliver(session, 1, isLast: true)

        await drain(session)

        XCTAssertEqual(session.id, openID, "The open conversation is never switched")
        XCTAssertEqual(session.notes, "My own meeting")
        XCTAssertTrue(session.segments.isEmpty)
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(watchRecords(session).count, 1)
        XCTAssertEqual(record.title, "Apple Watch · " + startedAt.formatted(date: .abbreviated, time: .shortened))
        XCTAssertEqual(record.date, startedAt)
        XCTAssertEqual(record.isComplete, true)
        XCTAssertEqual(record.segments?.map(\.text), ["The budget review moves to Friday.", "Sarah will send the numbers."])
        XCTAssertTrue(record.segments?.allSatisfy { $0.source == .you && $0.speakerName == "Apple Watch" } == true)
        XCTAssertEqual(record.transcript, "Apple Watch: The budget review moves to Friday.\nApple Watch: Sarah will send the numbers.")
        XCTAssertEqual(try archived().first, record, "Saved to the archive, not only kept in memory")
        XCTAssertEqual(session.message, "Apple Watch recording added to History.")
        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: session.watchInbox.root.appendingPathComponent(recordingID.uuidString).path),
            "The audio is deleted once it is text")
        XCTAssertEqual(fake.calls, [[0, 1]], "Both chunks go into one transcription")
    }

    func testRedeliveredChunkReopensTheSameConversation() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("First part.", chunk: 0)], 1: [line("Second part.", chunk: 1)],
                       2: [line("After Continue.", chunk: 2)]]
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 1, isLast: true)
        await drain(session)
        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)

        // The watch never heard that chunk 0 arrived and sends it again; then Continue adds chunk 2.
        try deliver(session, 0, at: startedAt.addingTimeInterval(hour))
        try deliver(session, 2, isLast: true, at: startedAt.addingTimeInterval(hour))
        await drain(session, now: startedAt.addingTimeInterval(hour + 60))

        XCTAssertEqual(watchRecords(session).count, 1, "The same conversation is reopened")
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.segments?.map(\.text), ["First part.", "Second part.", "After Continue."])
        XCTAssertEqual(record.isComplete, true)
        XCTAssertEqual(fake.calls, [[0, 1], [2]], "Audio already transcribed is not transcribed again")
        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)
        XCTAssertFalse(chunkExists(session, 0))
    }

    func testChunkAudioIsDeletedOnlyAfterItsTextIsSaved() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Kept as text.", chunk: 0)], 1: [line("Never said.", chunk: 1)]]
        fake.failAfter = (0, RecordingError.message("The audio is damaged."))
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 1, isLast: true)

        await drain(session)

        XCTAssertFalse(chunkExists(session, 0), "Chunk 0 is text now")
        XCTAssertTrue(chunkExists(session, 1), "A failed chunk is never deleted silently")
        let ledger = try XCTUnwrap(session.watchInbox.ledgers().first)
        XCTAssertEqual(ledger.failure, "The audio is damaged.")
        XCTAssertEqual(try archived().first?.segments?.map(\.text), ["Kept as text."])
        XCTAssertEqual(try archived().first?.isComplete, false)
        XCTAssertEqual(session.message, "Could not transcribe an Apple Watch recording: The audio is damaged. "
                       + "It is kept in History, where you can retry or delete it.")
        // A failed recording waits for the user; the next foreground does not retry it on its own.
        await drain(session)
        XCTAssertEqual(fake.calls.count, 1)
    }

    func testDrainNeverRunsWhileRecordingSummarizingOrInactive() async throws {
        let fake = FakeWatchTranscriber()
        let session = makeSession(fake)
        try deliver(session, 0, isLast: true)

        session.applicationIsActive = { false }
        await drain(session)
        session.applicationIsActive = { true }
        session.isSummarizing = true
        await drain(session)
        session.isSummarizing = false
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
        await drain(session)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertNil(session.watchDrainTask)

        await session.stop()
        await drain(session)
        XCTAssertEqual(fake.calls, [[0]])
    }

    func testStartingALiveRecordingCancelsTheDrainFirstAndItResumesWithoutDuplicates() async throws {
        let events = WatchEventLog()
        let fake = FakeWatchTranscriber(events: events)
        fake.script = [0: [line("Budget moves to Friday.", chunk: 0)], 1: [line("Sarah sends the numbers.", chunk: 1)]]
        fake.gateBefore = 1
        let session = makeSession(fake, recorder: EventLoggingRecorder(events: events))
        try deliver(session, 0)
        try deliver(session, 1, isLast: true)

        session.importWatchInbox(now: startedAt.addingTimeInterval(60))
        for _ in 0..<400 where !fake.isWaiting { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(fake.isWaiting)
        XCTAssertFalse(chunkExists(session, 0), "Chunk 0's text is saved, so its audio is gone")

        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(events.events, ["drainCancelled", "recorderStart"])
        XCTAssertNil(session.watchDrainTask)
        XCTAssertTrue(chunkExists(session, 1), "Audio not yet saved as text is kept")

        await session.stop()
        await drain(session)
        XCTAssertEqual(fake.calls, [[0, 1], [1]], "Resumes at the first chunk not transcribed")
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.segments?.map(\.text), ["Budget moves to Friday.", "Sarah sends the numbers."])
        XCTAssertEqual(record.isComplete, true)
    }

    func testAppendsToTheOpenConversationWhenItIsTheWatchRecording() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("First part.", chunk: 0)], 1: [line("Second part.", chunk: 1)]]
        let session = makeSession(fake)
        try deliver(session, 0)
        await drain(session)
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.isComplete, false)
        session.open(record)
        session.notes = "Typed while it was open"

        try deliver(session, 1, isLast: true)
        await drain(session)

        XCTAssertEqual(session.id, record.id)
        XCTAssertEqual(session.segments.map(\.text), ["First part.", "Second part."])
        XCTAssertEqual(session.notes, "Typed while it was open")
        XCTAssertEqual(try archived().first?.segments?.map(\.text), ["First part.", "Second part."])
        XCTAssertEqual(try archived().first?.notes, "Typed while it was open")
        // A relaunch restores the open conversation with everything in it.
        let relaunched = makeSession(FakeWatchTranscriber())
        XCTAssertEqual(relaunched.id, record.id)
        XCTAssertEqual(relaunched.segments.map(\.text), ["First part.", "Second part."])
    }

    func testGapNoteAppearsAfter24Hours() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Before the gap.", chunk: 0)], 2: [line("After the gap.", chunk: 2)]]
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 2, isLast: true)

        await drain(session, now: startedAt.addingTimeInterval(23 * hour))
        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text), ["Before the gap."])
        XCTAssertEqual(watchRecords(session).first?.notes ?? "", "")

        await drain(session, now: startedAt.addingTimeInterval(24 * hour))
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.segments?.map(\.text), ["Before the gap.", "After the gap."])
        XCTAssertEqual(record.notes, "Part of this recording (about 5 min) did not arrive from Apple Watch.")
        XCTAssertEqual(record.isComplete, true)
        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)
    }

    func testUnexpectedEndAddsItsNote() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Cut short.", chunk: 0)]]
        let session = makeSession(fake)
        try deliver(session, 0)
        let end = WatchRecordingEnd(recordingID: recordingID, startedAt: startedAt, lastIndex: 0, unexpected: true)
        session.watchInbox.acceptEnd(userInfo: end.userInfo, now: startedAt)

        await drain(session)

        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.notes, "This Apple Watch recording ended unexpectedly. The last few minutes may be missing.")
        XCTAssertEqual(record.isComplete, true)
    }

    func testUsesTheCurrentTranscriptionLanguage() async throws {
        let fake = FakeWatchTranscriber()
        let session = makeSession(fake)
        session.language = "fr_FR"
        try deliver(session, 0, isLast: true)
        await drain(session)
        XCTAssertEqual(fake.locales, [Locale(identifier: "fr_FR")])
    }

    func testTransientFileErrorLeavesTheRecordingForLater() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Eventually.", chunk: 0)]]
        fake.failBefore = (0, CocoaError(.fileWriteOutOfSpace))
        let session = makeSession(fake)
        try deliver(session, 0, isLast: true)

        await drain(session)
        let ledger = try XCTUnwrap(session.watchInbox.ledgers().first)
        XCTAssertNil(ledger.failure)
        XCTAssertTrue(chunkExists(session, 0))
        XCTAssertNotEqual(session.message, "Apple Watch recording added to History.")

        fake.failBefore = nil
        await drain(session)
        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text), ["Eventually."])
        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)
    }
}
