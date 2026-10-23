import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Settings → Save to folder (issue #53): notes are written at Stop and Save, never per live line,
/// and a failure stays visible and retryable, including after a relaunch.
@MainActor
final class MobileVaultTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var original: MarkdownVaultSync!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        folder = root.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "vault-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        original = MobileSession.markdownVault
    }

    override func tearDown() async throws {
        MobileSession.markdownVault = original
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeVault(enabled: Bool = true) -> MarkdownVaultSync {
        let vault = MarkdownVaultSync(defaults: defaults)
        vault.setEnabled(enabled)
        if enabled { XCTAssertTrue(vault.chooseFolder(folder)) }
        MobileSession.markdownVault = vault
        return vault
    }

    private func notes() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }
    }

    private func settle(_ vault: MarkdownVaultSync) async throws {
        for _ in 0..<400 where vault.status == .saving || !vault.pending.isEmpty && !vault.isFailing {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testOffByDefaultAndNothingIsWritten() async throws {
        let vault = MarkdownVaultSync(defaults: defaults)
        XCTAssertFalse(vault.enabled)
        XCTAssertEqual(vault.status, .off)
        MobileSession.markdownVault = vault
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"))
        session.notes = "Remember the budget"
        XCTAssertTrue(session.save())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(try notes(), [])
        XCTAssertTrue(vault.statusText.contains("Off"))
    }

    func testEnablingWithoutAFolderAsksForOne() {
        let vault = MarkdownVaultSync(defaults: defaults)
        vault.setEnabled(true)
        XCTAssertEqual(vault.status, .needsFolder)
        vault.save(SessionRecord(id: "a", title: "T", date: Date(), transcript: "", summary: ""))
        XCTAssertEqual(vault.status, .needsFolder)
        XCTAssertEqual(vault.unsavedIDs, ["a"], "the conversation is remembered until a folder is chosen")
        XCTAssertTrue(vault.statusText.contains("Choose a folder"))
        XCTAssertTrue(vault.needsAttention, "waiting notes show on the main screen, not only in Settings")
    }

    func testSaveWritesOneNoteThatTitleChangesUpdateInPlace() async throws {
        let vault = makeVault()
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"))
        session.notes = "Remember the budget"
        session.title = "Planning"
        XCTAssertTrue(session.save())
        try await settle(vault)
        session.title = "Budget planning"
        XCTAssertTrue(session.save())
        try await settle(vault)
        let names = try notes()
        XCTAssertEqual(names.count, 1, "\(names)")
        let text = try String(contentsOf: folder.appendingPathComponent(names[0]), encoding: .utf8)
        XCTAssertTrue(text.contains("# Budget planning"), text)
        XCTAssertTrue(text.contains("## Notes\n\nRemember the budget"), text)
        XCTAssertTrue(text.contains("tags:\n  - listentome"), text)
        XCTAssertTrue(vault.statusText.hasPrefix("Saved “"), vault.statusText)
        XCTAssertEqual(vault.unsavedIDs, [])
    }

    func testNothingIsWrittenWhileRecordingAndTheNoteAppearsAtStop() async throws {
        let vault = makeVault()
        let recorder = VaultTestRecorder()
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"), makeRecorder: { recorder })
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
        recorder.emit(TranscriptSegment(source: .you, text: "Ship it on Friday.", isFinal: true, start: 2, end: 4))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(session.segments.count, 1, "the line was saved to History")
        XCTAssertEqual(try notes(), [], "a live line is not written to the folder")

        await session.stop()
        try await settle(vault)
        let names = try notes()
        XCTAssertEqual(names.count, 1)
        let text = try String(contentsOf: folder.appendingPathComponent(names[0]), encoding: .utf8)
        XCTAssertTrue(text.contains("- [00:02] **"), text)
        XCTAssertTrue(text.contains("Ship it on Friday."), text)
        XCTAssertTrue(text.contains("language: \""), "the conversation's language is recorded")
    }

    func testAMissingFolderIsShownAndRetriedFromHistoryAfterARelaunch() async throws {
        let vault = makeVault()
        try FileManager.default.removeItem(at: folder)
        let session = MobileSession(storageDirectory: root.appendingPathComponent("app"))
        session.notes = "Keep me"
        XCTAssertTrue(session.save())
        try await settle(vault)
        XCTAssertTrue(vault.isFailing)
        guard case .failed(let failure) = vault.status else { return XCTFail("expected a failure") }
        XCTAssertTrue(failure.needsNewFolder)
        XCTAssertEqual(vault.unsavedIDs.count, 1)

        // Relaunch: the waiting note is remembered, and Retry rebuilds it from History.
        let relaunched = MarkdownVaultSync(defaults: defaults)
        XCTAssertEqual(relaunched.unsavedIDs, vault.unsavedIDs)
        XCTAssertTrue(relaunched.statusText.contains("not saved"), relaunched.statusText)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        relaunched.retry(history: session.history)
        try await settle(relaunched)
        XCTAssertEqual(try notes().count, 1)
        XCTAssertEqual(relaunched.unsavedIDs, [])
    }

    func testSaveAllWritesEveryConversationAndAChosenFolderWritesWhatWasWaiting() async throws {
        let vault = makeVault()
        let records = (0..<3).map {
            SessionRecord(id: UUID().uuidString, title: "C\($0)", date: Date(), transcript: "", summary: "S\($0)")
        }
        vault.saveAll(records)
        try await settle(vault)
        XCTAssertEqual(try notes().count, 3)

        vault.forgetFolder()
        XCTAssertEqual(vault.status, .needsFolder)
        vault.save(SessionRecord(id: "gone", title: "Deleted later", date: Date(), transcript: "", summary: ""))
        XCTAssertEqual(vault.unsavedIDs, ["gone"])
        XCTAssertTrue(vault.chooseFolder(folder))
        try await settle(vault)
        XCTAssertEqual(try notes().count, 4, "choosing a folder writes what was waiting")

        vault.setEnabled(false)
        XCTAssertEqual(vault.status, .off)
        XCTAssertTrue(vault.pending.isEmpty)
    }

    func testRetryForgetsConversationsDeletedFromHistorySinceTheRelaunch() {
        defaults.set(["deleted-meanwhile"], forKey: MarkdownVaultSync.unsavedKey)
        let vault = makeVault()
        XCTAssertEqual(vault.unsavedIDs, ["deleted-meanwhile"])
        vault.retry(history: [])
        XCTAssertEqual(vault.unsavedIDs, [])
        XCTAssertEqual(vault.status, .ready)
        XCTAssertEqual(defaults.stringArray(forKey: MarkdownVaultSync.unsavedKey), [])
    }
}

@MainActor
private final class VaultTestRecorder: MobileRecording {
    private var onSegment: (@MainActor (TranscriptSegment) -> Void)?

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { self.onSegment = onSegment }
    func stop() async throws { onSegment = nil }
    func reconfigure() async throws {}
    func emit(_ segment: TranscriptSegment) { onSegment?(segment) }
}
