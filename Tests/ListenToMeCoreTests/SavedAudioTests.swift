import XCTest
@testable import ListenToMeCore

/// Issue #55: raw audio is saved only on opt-in, lives in one folder per conversation, and is deleted
/// with the conversation, on request, or after the chosen retention.
final class SavedAudioTests: XCTestCase {
    private var root: URL!
    private let conversation = "2B8C9E0A-1111-4222-8333-944455556666"

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func library(excluded: Bool = true) -> SavedAudioLibrary {
        SavedAudioLibrary(root: root, excludeFromBackup: excluded)
    }

    /// Creates the file a writer would, then reports it finished.
    private func record(_ library: SavedAudioLibrary, sources: [SpeakerSource] = [.you], at date: Date = Date(),
                        offset: TimeInterval = 0, duration: TimeInterval = 30, trusted: Bool = true,
                        firstTimestamp: TimeInterval? = nil, id: String? = nil) throws -> [SavedAudioRun] {
        let id = id ?? conversation
        let runs = try library.beginRun(conversationID: id, sources: sources, startedAt: date,
                                        timelineOffset: offset, timesMatchAudio: trusted)
        for run in runs {
            let url = try XCTUnwrap(library.url(for: run, conversationID: id))
            try Data(repeating: 1, count: 1_000).write(to: url)
            library.finishRun(conversationID: id, fileName: run.fileName,
                              result: SavedAudioRunResult(duration: duration, firstTimestamp: firstTimestamp))
        }
        return runs
    }

    // MARK: Policy

    func testOffByDefaultAndRetentionFallsBackToKeep() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertFalse(SavedAudioPolicy.isEnabled(in: defaults), "Saving audio is opt-in")
        XCTAssertEqual(SavedAudioPolicy.retentionDays(in: defaults), 0)
        defaults.set(true, forKey: SavedAudioPolicy.enabledKey)
        defaults.set(30, forKey: SavedAudioPolicy.retentionDaysKey)
        XCTAssertTrue(SavedAudioPolicy.isEnabled(in: defaults))
        XCTAssertEqual(SavedAudioPolicy.retentionDays(in: defaults), 30)
        defaults.set(13, forKey: SavedAudioPolicy.retentionDaysKey)
        XCTAssertEqual(SavedAudioPolicy.retentionDays(in: defaults), 0, "An unknown value keeps audio")
        XCTAssertEqual(SavedAudioPolicy.retentionLabel(0), "Keep until I delete it")
        XCTAssertEqual(SavedAudioPolicy.retentionLabel(7), "Delete after 7 days")
    }

    func testStorageTextsAndLowStorage() {
        XCTAssertEqual(SavedAudioPolicy.usageText(bytes: 0), "No saved audio on this device.")
        XCTAssertTrue(SavedAudioPolicy.usageText(bytes: 12_000_000, device: "this Mac").hasSuffix("on this Mac."))
        XCTAssertTrue(SavedAudioPolicy.estimateText().contains("12"), SavedAudioPolicy.estimateText())
        XCTAssertTrue(SavedAudioPolicy.estimateText(tracks: 2).contains("24"), SavedAudioPolicy.estimateText(tracks: 2))
        XCTAssertNil(SavedAudioPolicy.startBlockedReason(availableBytes: nil))
        XCTAssertNil(SavedAudioPolicy.startBlockedReason(availableBytes: 5_000_000_000))
        XCTAssertNotNil(SavedAudioPolicy.startBlockedReason(availableBytes: 1_000))
        XCTAssertEqual(SavedAudioPolicy.timeLabel(0), "0:00")
        XCTAssertEqual(SavedAudioPolicy.timeLabel(245.9), "4:05")
        XCTAssertEqual(SavedAudioPolicy.timeLabel(3_723), "1:02:03")
        XCTAssertEqual(SavedAudioPolicy.timeLabel(-3), "0:00")
        XCTAssertEqual(SavedAudioPolicy.timeLabel(.nan), "0:00")
    }

    func testFailureMessagesKeepTranscriptionGoingAndNameAFullDisk() {
        let full = SavedAudioPolicy.failureMessage(CocoaError(.fileWriteOutOfSpace), availableBytes: nil)
        XCTAssertTrue(full.contains("storage is full"))
        XCTAssertTrue(full.contains("Transcription continues"))
        let posix = NSError(domain: "AudioFile", code: 1,
                            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        XCTAssertTrue(SavedAudioPolicy.failureMessage(posix, availableBytes: nil).contains("storage is full"))
        let nearlyFull = SavedAudioPolicy.failureMessage(CocoaError(.fileWriteUnknown), availableBytes: 10)
        XCTAssertTrue(nearlyFull.contains("storage is full"), "Almost no free space reads as a full disk")
        let other = SavedAudioPolicy.failureMessage(CocoaError(.fileWriteNoPermission), availableBytes: 9_000_000_000)
        XCTAssertFalse(other.contains("storage is full"))
        XCTAssertTrue(other.contains("Transcription continues"))
        XCTAssertTrue(SavedAudioPolicy.fellBehindMessage.contains("Transcription continues"))
    }

    // MARK: Paths

    func testConversationIDsCannotEscapeTheFolder() throws {
        let library = library()
        for bad in ["", "../x", "a/b", "..", String(repeating: "a", count: 200), "é"] {
            XCTAssertThrowsError(try library.directory(for: bad), bad)
            XCTAssertThrowsError(try library.beginRun(conversationID: bad, sources: [.you], startedAt: Date(),
                                                      timelineOffset: 0, timesMatchAudio: true), bad)
            XCTAssertEqual(library.runs(for: bad), [])
            XCTAssertEqual(library.bytes(for: bad), 0)
        }
        XCTAssertEqual(try library.directory(for: conversation).deletingLastPathComponent().standardizedFileURL,
                       root.standardizedFileURL)
        let run = SavedAudioRun(index: 1, source: .you, fileName: "../escape.m4a", startedAt: Date(),
                                timelineOffset: 0, timesMatchAudio: true)
        XCTAssertNil(library.url(for: run, conversationID: conversation))
        XCTAssertNil(library.url(for: run, conversationID: "../x"))
    }

    func testRunsGetNumberedFilesPerSourceAndAreExcludedFromBackup() throws {
        let library = library()
        let first = try record(library, sources: [.you, .others])
        let second = try record(library, sources: [.you])
        XCTAssertEqual(first.map(\.fileName), ["part-001-microphone.m4a", "part-001-system.m4a"])
        XCTAssertEqual(second.map(\.fileName), ["part-002-microphone.m4a"])
        let runs = library.runs(for: conversation)
        XCTAssertEqual(runs.map(\.fileName),
                       ["part-001-microphone.m4a", "part-001-system.m4a", "part-002-microphone.m4a"])
        XCTAssertEqual(runs.first?.duration, 30)
        XCTAssertEqual(runs[1].title(partCount: 2), "Part 1 · System audio")
        XCTAssertEqual(runs[0].title(partCount: 1), "Microphone")
        XCTAssertEqual(library.fileURLs(for: conversation).count, 3)
        XCTAssertTrue(library.hasAudio(conversation))
        XCTAssertEqual(library.bytes(for: conversation), library.totalBytes())
        XCTAssertGreaterThanOrEqual(library.totalBytes(), 3_000)
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(root))
    }

    func testTheMacsBackupIsLeftAloneWhenNotExcluded() throws {
        let library = library(excluded: false)
        _ = try record(library)
        XCTAssertFalse(PrivateStorage.isExcludedFromBackup(root))
    }

    func testAnEmptyOrMissingFileIsDroppedAndTheFolderGoesWithItsLastRun() throws {
        let library = library()
        let runs = try library.beginRun(conversationID: conversation, sources: [.you, .others], startedAt: Date(),
                                        timelineOffset: 0, timesMatchAudio: true)
        XCTAssertEqual(library.runs(for: conversation), [], "Nothing is listed before a file exists")
        for run in runs {
            library.finishRun(conversationID: conversation, fileName: run.fileName,
                              result: SavedAudioRunResult(duration: 0))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try library.directory(for: conversation).path))
        // A late finish after the folder is gone recreates nothing.
        library.finishRun(conversationID: conversation, fileName: runs[0].fileName,
                          result: SavedAudioRunResult(duration: 3))
        library.anchor(conversationID: conversation, index: 1, firstSegment: 4)
        library.finishRun(conversationID: "../bad", fileName: "x", result: SavedAudioRunResult(duration: 3))
        library.anchor(conversationID: "../bad", index: 1, firstSegment: 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try library.directory(for: conversation).path))
    }

    func testFinishRecordsFailureAndTheMacsFirstTimestamp() throws {
        let library = library()
        let runs = try library.beginRun(conversationID: conversation, sources: [.others], startedAt: Date(),
                                        timelineOffset: 0, timesMatchAudio: true)
        let url = try XCTUnwrap(library.url(for: runs[0], conversationID: conversation))
        try Data([1]).write(to: url)
        library.finishRun(conversationID: conversation, fileName: "unknown.m4a",
                          result: SavedAudioRunResult(duration: 9))
        library.finishRun(conversationID: conversation, fileName: runs[0].fileName,
                          result: SavedAudioRunResult(duration: 12, firstTimestamp: 1.5, failure: "Disk full"))
        library.anchor(conversationID: conversation, index: 1, firstSegment: 7)
        let saved = try XCTUnwrap(library.runs(for: conversation).first)
        XCTAssertEqual(saved.timelineOffset, 1.5)
        XCTAssertEqual(saved.failure, "Disk full")
        XCTAssertEqual(saved.firstSegment, 7)
    }

    func testAnUnreadableManifestReadsAsNoAudio() throws {
        let library = library()
        _ = try record(library)
        try Data("not json".utf8).write(to: try library.directory(for: conversation)
            .appendingPathComponent(SavedAudioLibrary.manifestName))
        XCTAssertEqual(library.runs(for: conversation), [])
    }

    // MARK: Retention and deletion

    func testDeletingOneConversationKeepsTheOthers() throws {
        let library = library()
        let other = "OTHER-1"
        _ = try record(library)
        _ = try record(library, id: other)
        try library.delete(conversationID: conversation)
        XCTAssertFalse(library.hasAudio(conversation))
        XCTAssertTrue(library.hasAudio(other))
        XCTAssertNoThrow(try library.delete(conversationID: conversation), "Deleting twice is not an error")
        XCTAssertThrowsError(try library.delete(conversationID: "../"))
        try library.deleteAll()
        XCTAssertFalse(library.hasAudio(other))
        XCTAssertEqual(library.totalBytes(), 0)
        XCTAssertNoThrow(try SavedAudioLibrary(root: root.appendingPathComponent("missing"), excludeFromBackup: true)
            .deleteAll())
    }

    func testExpiredRunsAreDeletedAndRecentOnesKept() throws {
        let library = library()
        let now = Date()
        _ = try record(library, at: now.addingTimeInterval(-40 * 86_400))
        _ = try record(library, at: now.addingTimeInterval(-2 * 86_400))
        _ = try record(library, at: now.addingTimeInterval(-40 * 86_400), id: "OLD-ONLY")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("not an id"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(library.deleteExpired(retentionDays: 0, now: now), 0, "0 keeps everything")
        XCTAssertEqual(library.deleteExpired(retentionDays: 30, now: now), 2)
        XCTAssertEqual(library.runs(for: conversation).map(\.index), [2])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try library.directory(for: "OLD-ONLY").path))
        XCTAssertEqual(library.deleteExpired(retentionDays: 30, now: now), 0)
    }

    // MARK: Seeking

    private func line(_ start: TimeInterval, _ source: SpeakerSource = .you) -> TranscriptSegment {
        TranscriptSegment(source: source, text: "line", isFinal: true, start: start, end: start + 2)
    }

    func testIPhoneLinesSeekIntoTheRunThatCoversTheirTime() {
        let first = SavedAudioRun(index: 1, source: .you, fileName: "a", startedAt: Date(), timelineOffset: 0,
                                  timesMatchAudio: true, duration: 60)
        let second = SavedAudioRun(index: 2, source: .you, fileName: "b", startedAt: Date(), timelineOffset: 62,
                                   timesMatchAudio: true)
        let runs = [second, first]
        XCTAssertEqual(SavedAudioSeek.target(for: line(10), index: 0, in: runs), .init(run: first, time: 10))
        XCTAssertEqual(SavedAudioSeek.target(for: line(70), index: 5, in: runs), .init(run: second, time: 8))
        XCTAssertNil(SavedAudioSeek.target(for: line(10, .others), index: 0, in: runs), "No file for that source")
        let gap = SavedAudioRun(index: 1, source: .you, fileName: "a", startedAt: Date(), timelineOffset: 0,
                                timesMatchAudio: true, duration: 5)
        XCTAssertNil(SavedAudioSeek.target(for: line(30), index: 0, in: [gap]), "Past the end of the file")
        let before = SavedAudioRun(index: 1, source: .you, fileName: "a", startedAt: Date(), timelineOffset: 40,
                                   timesMatchAudio: true)
        XCTAssertNil(SavedAudioSeek.target(for: line(10), index: 0, in: [before]),
                     "A line recorded before any saved run")
    }

    func testMacLinesSeekByRunOnlyWhereTheEngineReportsTimes() {
        let whisper = SavedAudioRun(index: 1, source: .others, fileName: "a", startedAt: Date(), timelineOffset: 1.5,
                                    timesMatchAudio: true, firstSegment: 0, duration: 120)
        let apple = SavedAudioRun(index: 2, source: .others, fileName: "b", startedAt: Date(), timelineOffset: 0,
                                  timesMatchAudio: false, firstSegment: 6)
        let runs = [whisper, apple]
        XCTAssertEqual(SavedAudioSeek.target(for: line(11.5, .others), index: 3, in: runs),
                       .init(run: whisper, time: 10))
        XCTAssertNil(SavedAudioSeek.target(for: line(0, .others), index: 7, in: runs),
                     "Apple's speech engines report no times, so the line cannot seek")
        XCTAssertEqual(SavedAudioSeek.target(for: line(0.5, .others), index: 0, in: runs)?.time, 0, "Clamped at 0")
    }

    func testAnUntimedLineNeverSeeks() {
        let run = SavedAudioRun(index: 1, source: .others, fileName: "a", startedAt: Date(), timelineOffset: 0,
                                timesMatchAudio: true, duration: 60)
        XCTAssertNil(SavedAudioSeek.target(for: TranscriptSegment(source: .others, text: "x", isFinal: true,
                                                                  start: 0, end: 0), index: 0, in: [run]))
    }

    // MARK: Review of #243

    func testUnfinishedRunsAreHiddenUntilFinishedAndTheCacheFollowsWrites() throws {
        let library = library()
        let runs = try library.beginRun(conversationID: conversation, sources: [.you], startedAt: Date(),
                                        timelineOffset: 0, timesMatchAudio: true)
        let url = try XCTUnwrap(library.url(for: runs[0], conversationID: conversation))
        try Data([1]).write(to: url)
        XCTAssertEqual(library.runs(for: conversation), [], "A run still being written is not playable or shareable")
        XCTAssertEqual(library.fileURLs(for: conversation), [])
        library.finishRun(conversationID: conversation, fileName: runs[0].fileName,
                          result: SavedAudioRunResult(duration: 5))
        XCTAssertEqual(library.runs(for: conversation).count, 1, "finishing invalidates the cached list")
        XCTAssertEqual(library.conversationIDs(), [conversation])
        try library.delete(conversationID: conversation)
        XCTAssertEqual(library.runs(for: conversation), [])
    }

    func testOrphanedAudioIsDeletedButKeptConversationsStay() throws {
        let library = library()
        _ = try record(library)
        _ = try record(library, id: "ORPHAN-1")
        _ = try record(library, id: "RECORDING-1")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("not an id"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(library.deleteOrphans(keeping: [conversation, "RECORDING-1"]), 1)
        XCTAssertEqual(Set(library.conversationIDs()), [conversation, "RECORDING-1"])
        XCTAssertTrue(library.hasAudio(conversation))
        XCTAssertFalse(library.hasAudio("ORPHAN-1"))
    }

    func testARunKilledMidRecordingIsRepairedOrPruned() throws {
        let library = library()
        let killed = try library.beginRun(conversationID: conversation, sources: [.you, .others], startedAt: Date(),
                                          timelineOffset: 0, timesMatchAudio: true)
        for run in killed { try Data([1]).write(to: try XCTUnwrap(library.url(for: run, conversationID: conversation))) }
        let recording = try library.beginRun(conversationID: "RECORDING-1", sources: [.you], startedAt: Date(),
                                             timelineOffset: 0, timesMatchAudio: true)
        try Data([1]).write(to: try XCTUnwrap(library.url(for: recording[0], conversationID: "RECORDING-1")))
        let changed = library.repairUnfinished(skipping: "RECORDING-1") { url in
            url.lastPathComponent.contains("microphone") ? 42 : nil
        }
        XCTAssertEqual(changed, 2)
        let runs = library.runs(for: conversation)
        XCTAssertEqual(runs.map(\.source), [.you], "The readable part plays; the unreadable one is deleted")
        XCTAssertEqual(runs.first?.duration, 42)
        XCTAssertEqual(library.repairUnfinished { _ in 1 }, 1, "Only the recording that was skipped is left")
        XCTAssertEqual(library.repairUnfinished { _ in 1 }, 0)
    }

    func testRetentionAgesAFolderWithAMissingOrDamagedIndexByItsFiles() throws {
        let library = library()
        let now = Date()
        _ = try record(library, id: "MISSING-1")
        _ = try record(library, id: "DAMAGED-1")
        _ = try record(library, id: "RECENT-1")
        let missing = try library.directory(for: "MISSING-1")
        try FileManager.default.removeItem(at: missing.appendingPathComponent(SavedAudioLibrary.manifestName))
        let damaged = try library.directory(for: "DAMAGED-1")
        try Data("{".utf8).write(to: damaged.appendingPathComponent(SavedAudioLibrary.manifestName))
        let old = now.addingTimeInterval(-40 * 86_400)
        for folder in [missing, damaged] {
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
            }
        }
        let recent = try library.directory(for: "RECENT-1")
        try FileManager.default.removeItem(at: recent.appendingPathComponent(SavedAudioLibrary.manifestName))
        XCTAssertEqual(library.deleteExpired(retentionDays: 30, now: now), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: damaged.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path), "Recent files stay, index or not")
    }

    /// The Mac's run offset comes from the session that is starting: every recording after the first
    /// continues the conversation's timeline (#233), so its file must start there too.
    @MainActor
    func testMacRunsArePlacedWhereEachRecordingsLinesStart() async throws {
        final class Holder: @unchecked Sendable {
            weak var session: MeetingSession?
            var offsets: [TimeInterval] = []
            var transcribers: [MockTranscriber] = []
        }
        let holder = Holder()
        let session = MeetingSession(
            store: ConversationStore(), context: ContextEngine(debounce: 0),
            makeCapture: {
                MainActor.assumeIsolated { holder.offsets.append(holder.session?.recordingOffset ?? -1) }
                return MockCapture()
            },
            makeTranscriber: { let made = MockTranscriber(); holder.transcribers.append(made); return made },
            makeProvider: { MockLLMProvider(id: $0, deltas: ["x"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"], clock: { 999_999 })
        session.proactiveEnabled = false
        holder.session = session
        func waitFor(_ count: Int) async {
            for _ in 0..<200 where session.store.utterances.count < count { try? await Task.sleep(nanoseconds: 10_000_000) }
        }
        try await session.start()
        holder.transcribers.last?.emit(TranscriptSegment(source: .others, text: "one", isFinal: true, start: 1, end: 20))
        await waitFor(1)
        await session.stopAndWait()
        try await session.start()
        holder.transcribers.last?.emit(TranscriptSegment(source: .others, text: "two", isFinal: true, start: 2, end: 4))
        await waitFor(2)
        await session.stopAndWait()
        XCTAssertEqual(holder.offsets, [0, 20])

        let library = library()
        var runs: [SavedAudioRun] = []
        for (number, offset) in holder.offsets.enumerated() {
            let run = try library.beginRun(conversationID: conversation, sources: [.others], startedAt: Date(),
                                           timelineOffset: offset, timesMatchAudio: true)[0]
            try Data([1]).write(to: try XCTUnwrap(library.url(for: run, conversationID: conversation)))
            library.finishRun(conversationID: conversation, fileName: run.fileName,
                              result: SavedAudioRunResult(duration: 60, firstTimestamp: 0.5))
            library.anchor(conversationID: conversation, index: run.index, firstSegment: number)
        }
        runs = library.runs(for: conversation)
        let lines = session.store.utterances
        XCTAssertEqual(lines.map(\.start), [1, 22])
        let second = try XCTUnwrap(SavedAudioSeek.target(for: lines[1], index: 1, in: runs))
        XCTAssertEqual(second.run.index, 2)
        XCTAssertEqual(second.time, 1.5, accuracy: 0.001, "2 s into the second recording, less its first chunk's 0.5 s")
        XCTAssertEqual(SavedAudioSeek.target(for: lines[0], index: 0, in: runs)?.time ?? -1, 0.5, accuracy: 0.001)
    }

    /// The Mac keeps audio only for a conversation in History; it asks the archive.
    func testTheArchiveSaysWhetherAConversationIsSaved() throws {
        let archive = SessionArchive(directory: root.appendingPathComponent("Conversations"))
        XCTAssertFalse(archive.contains(id: conversation))
        try archive.save(SessionRecord(id: conversation, title: "T", date: Date(), transcript: "", summary: ""))
        XCTAssertTrue(archive.contains(id: conversation))
        XCTAssertFalse(archive.contains(id: "../escape"))
    }
}
