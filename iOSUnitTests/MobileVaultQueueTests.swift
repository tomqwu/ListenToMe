import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Save to folder's queue (issue #53 review): one bad note never blocks the rest, deleted
/// conversations are never written, the recording conversation is left alone, the setting being off
/// means nothing is queued, Apple Watch conversations are written too, and quitting can wait for writes.
@MainActor
final class MobileVaultQueueTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var original: MarkdownVaultSync!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vaultq-\(UUID().uuidString)")
        folder = root.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "vault-queue-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        original = MobileSession.markdownVault
    }

    override func tearDown() async throws {
        MobileSession.markdownVault = original
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeVault(write: MarkdownVaultWriter.Write? = nil) -> MarkdownVaultSync {
        let vault = MarkdownVaultSync(defaults: defaults) { bookmark in
            write.map { MarkdownVaultWriter(bookmark: bookmark, write: $0) } ?? MarkdownVaultWriter(bookmark: bookmark)
        }
        vault.setEnabled(true)
        XCTAssertTrue(vault.chooseFolder(folder))
        MobileSession.markdownVault = vault
        return vault
    }

    private func notes() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }.sorted()
    }

    private func settle(_ vault: MarkdownVaultSync) async throws {
        for _ in 0..<400 where vault.status == .saving || (!vault.pending.isEmpty && !vault.isFailing) {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func record(_ title: String, id: String = UUID().uuidString) -> SessionRecord {
        SessionRecord(id: id, title: title, date: Date(), transcript: "", summary: "Summary of \(title)")
    }

    func testOneNoteStuckInICloudDoesNotHoldUpTheOthers() async throws {
        let vault = makeVault()
        let stuck = record("Stuck"), fine = record("Fine")
        let placeholder = ".2026-01-01 0900 " + MarkdownVault.marker(for: stuck.id) + ".icloud"
        try Data().write(to: folder.appendingPathComponent(placeholder))
        vault.saveAll([stuck, fine])
        try await settle(vault)
        XCTAssertEqual(try notes().count, 1, "the other conversation is written")
        XCTAssertNotNil(vault.pending[stuck.id], "the stuck note stays queued")
        XCTAssertEqual(vault.noteFailures[stuck.id]?.kind, .iCloudPending)
        XCTAssertEqual(vault.unsavedIDs, [stuck.id])
        XCTAssertTrue(vault.isFailing)
        XCTAssertTrue(vault.needsAttention)

        // Once the placeholder is gone (downloaded), Retry writes it.
        try FileManager.default.removeItem(at: folder.appendingPathComponent(placeholder))
        vault.retry(history: [stuck, fine])
        try await settle(vault)
        XCTAssertEqual(try notes().count, 2)
        XCTAssertTrue(vault.noteFailures.isEmpty)
        XCTAssertFalse(vault.needsAttention)
    }

    func testAFullDiskStopsTheQueueWithEveryNoteKept() async throws {
        let vault = makeVault { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        vault.saveAll([record("A"), record("B")])
        try await settle(vault)
        guard case .failed(let failure) = vault.status else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .diskFull)
        XCTAssertEqual(vault.pending.count, 2)
        XCTAssertEqual(vault.unsavedIDs.count, 2)
    }

    /// Naming a conversation automatically (#221) rewrites its note's title in place: one file.
    func testAnAutomaticNameUpdatesTheSameNote() async throws {
        let vault = makeVault()
        let saved = UserDefaults.standard.object(forKey: MobileSession.autoTitleKey)
        defer { UserDefaults.standard.set(saved, forKey: MobileSession.autoTitleKey) }
        UserDefaults.standard.removeObject(forKey: MobileSession.autoTitleKey)
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"),
                                    sharedInbox: root.appendingPathComponent("inbox"))
        session.ai.provider = .apple
        session.onDeviceProviderOverride = MobileAutoTitleTests.TitleProvider("Spring marketing budget")
        session.segments = MobileAutoTitleTests.meeting.enumerated().map {
            TranscriptSegment(source: .you, text: $1, isFinal: true, start: Double($0), end: Double($0) + 1)
        }
        XCTAssertTrue(session.save())
        try await settle(vault)
        XCTAssertEqual(try notes().count, 1)
        session.nameConversationIfNeeded()
        await session.autoTitleTasks[session.id]?.value
        try await settle(vault)
        let files = try notes()
        XCTAssertEqual(files.count, 1, "renamed in place, not duplicated")
        let text = try String(contentsOf: folder.appendingPathComponent(files[0]), encoding: .utf8)
        XCTAssertTrue(text.contains("title: \"Spring marketing budget\""), text)
    }

    func testDeletingAConversationDropsItsQueuedNote() async throws {
        let vault = makeVault()
        try FileManager.default.removeItem(at: folder)
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"))
        session.notes = "Delete me"
        XCTAssertTrue(session.save())
        let deleted = session.id
        try await settle(vault)
        XCTAssertNotNil(vault.pending[deleted])
        session.deleteConversation(id: deleted)
        XCTAssertNil(vault.pending[deleted])
        XCTAssertFalse(vault.unsavedIDs.contains(deleted))

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        vault.retry(history: session.history)
        try await settle(vault)
        XCTAssertEqual(try notes(), [], "a deleted transcript is never written")
        vault.save(record("Kept"))
        vault.forgetAll()
        XCTAssertTrue(vault.pending.isEmpty)
        XCTAssertTrue(vault.unsavedIDs.isEmpty)
    }

    func testRetryAndSaveAllQueueNothingWhileOff() {
        defaults.set(["waiting"], forKey: MarkdownVaultSync.unsavedKey)
        let vault = MarkdownVaultSync(defaults: defaults)
        XCTAssertFalse(vault.enabled)
        vault.retry(history: [record("Waiting", id: "waiting")])
        vault.saveAll([record("Other")])
        XCTAssertTrue(vault.pending.isEmpty)
        XCTAssertFalse(vault.needsAttention)
    }

    func testSaveAllAndRetrySkipTheRecordingConversationAndKeepTheLanguage() async throws {
        let vault = makeVault()
        let recording = record("Recording"), done = record("Done")
        vault.saveAll([recording, done], language: "fr_FR", excluding: recording.id)
        try await settle(vault)
        let names = try notes()
        XCTAssertEqual(names.count, 1)
        let text = try String(contentsOf: folder.appendingPathComponent(names[0]), encoding: .utf8)
        XCTAssertTrue(text.contains("# Done"), text)
        XCTAssertTrue(text.contains("language: \"fr-FR\""), "the same language field ordinary saves write")
        XCTAssertNil(vault.pending[recording.id])

        vault.activeRecordingID = recording.id
        defaults.set([recording.id], forKey: MarkdownVaultSync.unsavedKey)
        let relaunched = MarkdownVaultSync(defaults: defaults)
        relaunched.activeRecordingID = recording.id
        relaunched.retry(history: [recording])
        XCTAssertNil(relaunched.pending[recording.id], "Retry leaves the recording conversation alone")
        XCTAssertEqual(relaunched.unsavedIDs, [recording.id], "and still remembers it")
    }

    func testTheSessionHidesTheRecordingConversationOnlyWhileRecording() {
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"))
        XCTAssertNil(session.vaultRecordingID)
    }

    func testWaitingForWritesIsBounded() async throws {
        let vault = makeVault { data, url in
            Thread.sleep(forTimeInterval: 1)
            try MarkdownVaultWriter.coordinatedWrite(data, url)
        }
        vault.save(record("Slow"))
        let clock = ContinuousClock()
        let waited = await clock.measure { await vault.waitForWrites(timeout: .milliseconds(100)) }
        XCTAssertLessThan(waited, .milliseconds(900), "quitting never waits longer than the bound")
        await vault.waitForWrites(timeout: .seconds(5))
        XCTAssertEqual(try notes().count, 1, "and a write that finishes in time is complete")
    }

    func testAnAppleWatchConversationIsSavedToTheFolder() async throws {
        let vault = makeVault()
        let fake = FakeWatchTranscriber()
        fake.script = [0: [FakeWatchTranscriber.Line(text: "Budget moves to Friday.", start: 10, end: 300)]]
        let app = root.appendingPathComponent("app")
        let session = MobileSession(storageDirectory: app, makeRecorder: { LifecycleTestRecorder() },
                                    makeWatchTranscriber: { fake })
        session.applicationIsActive = { true }
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let source = root.appendingPathComponent("chunk.m4a")
        try Data(repeating: 1, count: 32).write(to: source)
        let metadata = WatchChunkMetadata(recordingID: UUID(), index: 0, startOffset: 0, duration: 300,
                                          isLast: true, startedAt: started, watchBuild: "28")
        XCTAssertEqual(session.watchInbox.accept(fileAt: source, metadata: metadata.transferMetadata, now: started),
                       .stored)
        session.importWatchInbox(now: started.addingTimeInterval(60))
        await session.watchDrainTask?.value
        try await settle(vault)
        let names = try notes()
        XCTAssertEqual(names.count, 1, "\(names)")
        let text = try String(contentsOf: folder.appendingPathComponent(names[0]), encoding: .utf8)
        XCTAssertTrue(text.contains("Budget moves to Friday."), text)
        XCTAssertTrue(text.contains("**Apple Watch:**"), text)
    }
}
