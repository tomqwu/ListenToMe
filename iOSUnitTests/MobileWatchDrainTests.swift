import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// Apple Watch recordings become conversations in the foreground (issue #181).
@MainActor
final class MobileWatchDrainTests: XCTestCase {
    private var root: URL!
    private var savedLanguage: Any?
    private var savedAutomatic: Any?
    private let recordingID = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let hour: TimeInterval = 3_600

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        savedLanguage = UserDefaults.standard.object(forKey: MobileSession.languageKey)
        savedAutomatic = UserDefaults.standard.object(forKey: MobileLanguageDetection.automaticKey)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.set(savedLanguage, forKey: MobileSession.languageKey)
        UserDefaults.standard.set(savedAutomatic, forKey: MobileLanguageDetection.automaticKey)
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

    /// Delivers chunk `index` (300 s each unless told otherwise) as if WatchConnectivity handed it
    /// over at `at`.
    private func deliver(_ session: MobileSession, _ index: Int, isLast: Bool = false, at: Date? = nil,
                         recording: UUID? = nil, startedAt started: Date? = nil, startOffset: TimeInterval? = nil,
                         duration: TimeInterval = 300, expect: WatchInbox.Acceptance = .stored,
                         line: UInt = #line) throws {
        let source = root.appendingPathComponent("delivery-\(UUID().uuidString).m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: source)
        let metadata = WatchChunkMetadata(recordingID: recording ?? recordingID, index: index,
                                          startOffset: startOffset ?? TimeInterval(index) * 300, duration: duration,
                                          isLast: isLast, startedAt: started ?? startedAt, watchBuild: "28")
        let stored = session.watchInbox.accept(fileAt: source, metadata: metadata.transferMetadata, now: at ?? startedAt)
        XCTAssertEqual(stored, expect, line: line)
    }

    /// Recordings with anything still to do; a completed one stays only as a tombstone.
    private func waiting(_ session: MobileSession) -> [WatchCaptureLedger] {
        session.watchInbox.ledgers().filter { !$0.completed }
    }

    private func audioFiles(_ session: MobileSession, _ recording: UUID? = nil) -> [String] {
        let folder = session.watchInbox.root.appendingPathComponent((recording ?? recordingID).uuidString)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".m4a") }
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
        XCTAssertTrue(waiting(session).isEmpty)
        XCTAssertEqual(audioFiles(session), [], "The audio is deleted once it is text")
        XCTAssertEqual(fake.calls, [[0, 1]], "Both chunks go into one transcription")
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
        XCTAssertTrue(waiting(session).isEmpty)
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
        session.languageChoice = "fr_FR"
        try deliver(session, 0, isLast: true)
        await drain(session)
        XCTAssertEqual(fake.locales, [Locale(identifier: "fr_FR")])
    }

    /// Issue #197: Automatic transcribes a watch recording in the device's language; detection is live-only.
    func testAutomaticTranscribesInTheDeviceLanguage() async throws {
        let fake = FakeWatchTranscriber()
        let session = makeSession(fake)
        session.language = "fr_FR"
        session.languageChoice = MobileSession.automaticLanguageTag
        try deliver(session, 0, isLast: true)
        await drain(session)
        XCTAssertEqual(fake.locales, [Locale(identifier: Locale.current.identifier)])
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
        XCTAssertTrue(waiting(session).isEmpty)
    }

    // MARK: History rows (Task 13)

    func testRowsListWaitingAndFailedRecordings() async throws {
        let fake = FakeWatchTranscriber()
        fake.failBefore = (0, RecordingError.message("The audio is damaged."))
        let session = makeSession(fake)
        let waiting = UUID(), finished = UUID()
        try deliver(session, 0, isLast: true)
        await drain(session)
        try deliver(session, 1, recording: waiting, startedAt: startedAt.addingTimeInterval(hour))
        try deliver(session, 2, recording: waiting, startedAt: startedAt.addingTimeInterval(hour))
        try deliver(session, 0, recording: finished, startedAt: startedAt.addingTimeInterval(2 * hour))
        _ = try session.watchInbox.update(finished) { $0.markTranscribed(through: 300) }

        session.refreshWatchInboxRows()

        XCTAssertEqual(session.watchInboxRows, [
            WatchInboxRow(id: recordingID, startedAt: startedAt, waitingParts: 1, failure: "The audio is damaged."),
            WatchInboxRow(id: waiting, startedAt: startedAt.addingTimeInterval(hour), waitingParts: 2, failure: nil),
        ], "A recording with nothing left to transcribe is not listed")
        XCTAssertEqual(session.watchInboxRows[0].title,
                       "Apple Watch · " + startedAt.formatted(date: .abbreviated, time: .shortened))
        XCTAssertEqual(session.watchInboxRows[0].detail, "The audio is damaged.")
        XCTAssertEqual(session.watchInboxRows[1].detail, "2 parts waiting")
        XCTAssertEqual(WatchInboxRow(id: waiting, startedAt: startedAt, waitingParts: 1, failure: nil).detail,
                       "1 part waiting")
    }

    func testRetryClearsTheFailureAndDrains() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Second time lucky.", chunk: 0)]]
        fake.failBefore = (0, RecordingError.message("The speech model was busy."))
        let session = makeSession(fake)
        try deliver(session, 0, isLast: true)
        await drain(session)
        XCTAssertEqual(session.watchInboxRows.first?.failure, "The speech model was busy.", "Rows refresh after a drain")

        fake.failBefore = nil
        session.retryWatchRecording(recordingID)
        await session.watchDrainTask?.value

        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text), ["Second time lucky."])
        XCTAssertTrue(waiting(session).isEmpty)
        XCTAssertTrue(session.watchInboxRows.isEmpty)
        XCTAssertEqual(session.message, "Apple Watch recording added to History.")
    }

    func testDeleteRemovesOnlyTheAudioAndKeepsTheConversation() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Already text.", chunk: 0)]]
        fake.failAfter = (0, RecordingError.message("The audio is damaged."))
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 1, isLast: true)
        await drain(session)
        XCTAssertEqual(session.watchInboxRows.count, 1)

        session.deleteWatchRecording(recordingID)

        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: session.watchInbox.root.appendingPathComponent(recordingID.uuidString).path))
        XCTAssertTrue(session.watchInboxRows.isEmpty)
        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text), ["Already text."])
        XCTAssertEqual(try archived().first?.segments?.map(\.text), ["Already text."])
    }

    func testRecordsFromTheWatchAreFlagged() {
        func record(_ source: String?) -> SessionRecord {
            SessionRecord(id: UUID().uuidString, title: "A", date: startedAt, transcript: "", summary: "",
                          sourceImportID: source)
        }
        XCTAssertTrue(MobileSession.isFromAppleWatch(record("watch:\(recordingID.uuidString)")))
        XCTAssertFalse(MobileSession.isFromAppleWatch(record(UUID().uuidString)), "A share-sheet import")
        XCTAssertFalse(MobileSession.isFromAppleWatch(record(nil)))
    }
}

/// Review follow-ups: Continue and reopen, storage failures, deletion and batching.
extension MobileWatchDrainTests {
    /// Real lines rarely end on a chunk boundary, and Continue starts at the wall-clock offset.
    func testRedeliveredChunkAndContinueReopenTheSameConversationWithoutAGap() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [FakeWatchTranscriber.Line(text: "First part.", start: 12, end: 287.4)],
                       1: [FakeWatchTranscriber.Line(text: "Second part.", start: 301, end: 590.2)],
                       2: [FakeWatchTranscriber.Line(text: "After Continue.", start: 671, end: 902.5)],
                       3: [FakeWatchTranscriber.Line(text: "The end.", start: 965, end: 1_010)]]
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 1, isLast: true, duration: 297.8)
        await drain(session)
        XCTAssertEqual(session.message, "Apple Watch recording added to History.")
        XCTAssertTrue(waiting(session).isEmpty)

        // The watch never heard that chunk 0 arrived and sends it again; then Continue adds chunk 2,
        // which is not the last.
        let later = startedAt.addingTimeInterval(hour)
        try deliver(session, 0, at: later, expect: .duplicate)
        try deliver(session, 2, at: later, startOffset: 660)
        session.message = nil
        await drain(session, now: later.addingTimeInterval(60))
        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text), ["First part.", "Second part.", "After Continue."])
        XCTAssertNil(session.message, "Continue is still going")
        // A day later with nothing more, the recording is over, and nothing is reported missing.
        await drain(session, now: later.addingTimeInterval(25 * hour))
        XCTAssertEqual(watchRecords(session).count, 1, "The same conversation is reopened")
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.notes ?? "", "", "No false gap note")
        XCTAssertEqual(record.isComplete, true)
        XCTAssertEqual(fake.calls, [[0, 1], [2]], "Audio already transcribed is not transcribed again")
        XCTAssertEqual(audioFiles(session), [])

        // Another Continue part lands in the same conversation too.
        try deliver(session, 3, isLast: true, at: later.addingTimeInterval(26 * hour), startOffset: 960, duration: 60)
        await drain(session, now: later.addingTimeInterval(26 * hour))
        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text).last, "The end.")
        XCTAssertEqual(watchRecords(session).first?.notes ?? "", "")
    }

    func testLateEndMarkerAddsNoGapNote() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [FakeWatchTranscriber.Line(text: "All of it.", start: 3, end: 241.7)]]
        let session = makeSession(fake)
        try deliver(session, 0, isLast: true, duration: 250)
        await drain(session)
        let end = WatchRecordingEnd(recordingID: recordingID, startedAt: startedAt, lastIndex: 0, unexpected: true)
        session.watchInbox.acceptEnd(userInfo: end.userInfo, now: startedAt.addingTimeInterval(hour))
        await drain(session, now: startedAt.addingTimeInterval(30 * hour))
        XCTAssertEqual(watchRecords(session).count, 1)
        XCTAssertEqual(watchRecords(session).first?.notes ?? "", "")
        XCTAssertEqual(fake.calls, [[0]])
    }

    /// The manifest and audio were deleted from History; a Continue part arriving later must not wait
    /// a day for chunks the conversation already holds.
    func testReopeningAfterTheAudioWasDeletedNeedsNoGap() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [FakeWatchTranscriber.Line(text: "Before.", start: 5, end: 280.3)],
                       2: [FakeWatchTranscriber.Line(text: "After.", start: 700, end: 801)]]
        fake.failBefore = (1, RecordingError.message("The audio is damaged."))
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 1, isLast: true)
        await drain(session)
        session.deleteWatchRecording(recordingID)
        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)

        try deliver(session, 2, isLast: true, at: startedAt.addingTimeInterval(hour), startOffset: 690)
        await drain(session, now: startedAt.addingTimeInterval(hour + 60))
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertEqual(record.segments?.map(\.text), ["Before.", "After."])
        XCTAssertEqual(record.notes ?? "", "")
        XCTAssertEqual(record.isComplete, true)
    }

    /// A crash after the lines were saved but before the manifest said so must not repeat them.
    func testSavedLinesAreNotRepeatedWhenTheManifestLagsBehind() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [FakeWatchTranscriber.Line(text: "Once.", start: 4, end: 120.5),
                           FakeWatchTranscriber.Line(text: "Twice?", start: 130, end: 250)]]
        fake.failAfter = (0, CocoaError(.fileWriteOutOfSpace))
        let session = makeSession(fake)
        try deliver(session, 0, isLast: true)
        await drain(session)
        // Rewind the manifest as if the mark never reached the disk.
        var stale = WatchCaptureLedger(recordingID: recordingID, startedAt: startedAt, at: startedAt)
        stale.receive(WatchChunkMetadata(recordingID: recordingID, index: 0, startOffset: 0, duration: 300,
                                         isLast: true, startedAt: startedAt, watchBuild: "28"), at: startedAt)
        try session.watchInbox.save(stale)

        fake.failAfter = nil
        await drain(session)
        XCTAssertEqual(watchRecords(session).first?.segments?.map(\.text), ["Once.", "Twice?"])
    }

    func testDeletingAWatchConversationDiscardsItsAudio() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("Private words.", chunk: 0)], 2: [line("More.", chunk: 2)]]
        let session = makeSession(fake)
        try deliver(session, 0)
        try deliver(session, 2, isLast: true)
        await drain(session)
        let record = try XCTUnwrap(watchRecords(session).first)
        XCTAssertFalse(audioFiles(session).isEmpty, "Chunk 2 waits for the missing chunk 1")

        session.deleteConversation(id: record.id)

        XCTAssertTrue(session.watchInbox.ledgers().isEmpty)
        XCTAssertEqual(audioFiles(session), [], "No raw audio remains")
        await drain(session, now: startedAt.addingTimeInterval(30 * hour))
        XCTAssertTrue(watchRecords(session).isEmpty, "The deleted conversation does not come back")
        XCTAssertTrue(try archived().isEmpty)

        // The watch sends an old part again (#191): it is discarded, not a new conversation.
        let later = startedAt.addingTimeInterval(31 * hour)
        try deliver(session, 0, at: later, expect: .discarded)
        await drain(session, now: later.addingTimeInterval(60))
        XCTAssertTrue(watchRecords(session).isEmpty)
        XCTAssertEqual(audioFiles(session), [])
    }

    func testAChunkArrivingDuringADrainIsTranscribedAfterIt() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: [line("First recording.", chunk: 0)]]
        fake.gateBefore = 0
        let session = makeSession(fake)
        try deliver(session, 0, isLast: true)
        session.importWatchInbox(now: startedAt.addingTimeInterval(60))
        for _ in 0..<400 where !fake.isWaiting { try await Task.sleep(for: .milliseconds(5)) }

        let other = UUID()
        try deliver(session, 0, isLast: true, recording: other, startedAt: startedAt.addingTimeInterval(hour))
        session.importWatchInbox()   // what the link does when a chunk arrives
        fake.release()
        for _ in 0..<400 where fake.calls.count < 2 || session.watchDrainTask != nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(fake.calls, [[0], [0]], "The second recording is not stranded until the next foreground")
        XCTAssertNotNil(session.history.first { $0.sourceImportID == "watch:\(other.uuidString)" })
    }

    func testLinesAreSavedInBatchesAndAudioGoesOnlyAfterTheSaveThatCoversIt() async throws {
        let fake = FakeWatchTranscriber()
        fake.script = [0: (0..<30).map {
            FakeWatchTranscriber.Line(text: "Line \($0).", start: Double($0) * 9, end: Double($0) * 9 + 8)
        }]
        var archivedAtLine: [Int: Int] = [:]
        var audioAtLine: [Int: Bool] = [:]
        let session = makeSession(fake)
        fake.onLine = { [unowned self] count in
            archivedAtLine[count] = (try? self.archived().first?.segments?.count) ?? 0
            audioAtLine[count] = self.chunkExists(session, 0)
        }
        try deliver(session, 0, isLast: true, duration: 280)
        await drain(session)

        XCTAssertEqual(archivedAtLine[3], 0, "Not one save per line")
        XCTAssertEqual(archivedAtLine[26], 25, "Saved after 25 lines")
        XCTAssertEqual(audioAtLine[26], true, "The chunk's audio waits for the save that covers its end")
        XCTAssertEqual(watchRecords(session).first?.segments?.count, 30)
        XCTAssertFalse(chunkExists(session, 0))
    }

    func testRefusedAudioIsShownInHistoryUntilDismissed() throws {
        let session = makeSession(FakeWatchTranscriber())
        session.watchInbox.clearProblems()
        let source = root.appendingPathComponent("huge.m4a")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(count: WatchChunkMetadata.maximumFileBytes + 1).write(to: source)
        let metadata = WatchChunkMetadata(recordingID: recordingID, index: 0, startOffset: 0, duration: 300,
                                          isLast: true, startedAt: startedAt, watchBuild: "28")
        _ = session.watchInbox.accept(fileAt: source, metadata: metadata.transferMetadata, now: startedAt)
        session.refreshWatchInboxRows()
        XCTAssertEqual(session.watchInboxProblems.count, 1)
        session.dismissWatchInboxProblems()
        XCTAssertTrue(session.watchInboxProblems.isEmpty)
        XCTAssertTrue(session.watchInbox.problems().isEmpty)
    }
}
