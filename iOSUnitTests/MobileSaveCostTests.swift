import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// `save()` used to re-read, decode and sort every archived conversation, and Notes/title edits
/// saved on every keystroke. These tests pin the cheap behaviour: in-memory history, no write when
/// nothing changed, and debounced typing.
@MainActor
final class MobileSaveCostTests: XCTestCase {
    private func makeRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    private func conversation(_ root: URL, _ id: String) -> URL {
        root.appendingPathComponent("Conversations", isDirectory: true).appendingPathComponent("\(id).json")
    }

    func testSavingUpdatesHistoryInMemoryWithoutRescanningTheArchive() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.notes = "First"
        XCTAssertTrue(session.save(announce: false))
        let id = try XCTUnwrap(session.history.first?.id)

        // Only a full archive rescan would notice this file.
        let planted = SessionRecord(id: "planted", title: "Planted", date: Date(), transcript: "",
                                    summary: "", segments: [], notes: "planted")
        try JSONEncoder().encode(planted).write(to: conversation(root, "planted"))

        session.notes = "First and second"
        XCTAssertTrue(session.save(announce: false))
        XCTAssertEqual(session.history.count, 1, "save() must not re-read the archive")
        XCTAssertEqual(session.history.first?.id, id)
        XCTAssertEqual(session.history.first?.notes, "First and second", "The in-memory entry must be replaced")

        // Launching again still reads the archive, so nothing is lost.
        let relaunched = MobileSession(storageDirectory: root)
        XCTAssertEqual(Set(relaunched.history.map(\.id)), [id, "planted"])
    }

    func testAnUnchangedRecordIsNotWrittenAgain() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.notes = "Stable"
        XCTAssertTrue(session.save(announce: false))
        let url = conversation(root, try XCTUnwrap(session.history.first?.id))

        try Data("sentinel".utf8).write(to: url)
        XCTAssertTrue(session.save(announce: false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "sentinel",
                       "An unchanged record must skip the archive write")

        session.notes = "Changed"
        XCTAssertTrue(session.save(announce: false))
        XCTAssertNotEqual(try String(contentsOf: url, encoding: .utf8), "sentinel")
    }

    func testAnAlreadySavedConversationCanPersistAnEmptyEdit() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.notes = "Text to clear"
        XCTAssertTrue(session.save(announce: false))
        let id = try XCTUnwrap(session.history.first?.id)
        session.notes = ""
        XCTAssertFalse(session.hasContent)
        XCTAssertTrue(session.save(announce: false))
        let archived = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: conversation(root, id)))
        XCTAssertEqual(archived.notes ?? "", "")
        XCTAssertEqual(session.history.first?.id, id)
        XCTAssertEqual(session.history.first?.notes ?? "", "")
    }

    func testArchiveFailureKeepsCurrentTextAndCanRetry() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        let archive = root.appendingPathComponent("Conversations")
        try? FileManager.default.removeItem(at: archive)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("Not a directory".utf8).write(to: archive)
        session.notes = "Keep this unsaved text"
        XCTAssertFalse(session.save())
        XCTAssertEqual(session.notes, "Keep this unsaved text")
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.activeURL.path))
        XCTAssertTrue(session.message?.contains("Could not save conversation") == true)
        try FileManager.default.removeItem(at: archive)
        XCTAssertTrue(session.save())
        XCTAssertEqual(session.history.first?.notes, "Keep this unsaved text")
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.activeURL.path))
    }

    func testActiveSnapshotFailureStaysRetryableAfterArchiveWasSaved() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        try FileManager.default.createDirectory(at: session.activeURL, withIntermediateDirectories: true)
        session.notes = "Retry the same bytes"
        XCTAssertFalse(session.save())
        let id = try XCTUnwrap(session.history.first?.id)
        XCTAssertEqual(session.history.first?.notes, "Retry the same bytes", "Archive succeeded before active snapshot failed")
        XCTAssertEqual(session.notes, "Retry the same bytes")
        let archivedURL = conversation(root, id)
        try Data("sentinel".utf8).write(to: archivedURL)
        try FileManager.default.removeItem(at: session.activeURL)
        XCTAssertTrue(session.save(), "A partial failure cannot acknowledge unchanged bytes as saved")
        let archived = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: archivedURL))
        let active = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: session.activeURL))
        XCTAssertEqual(archived.notes, "Retry the same bytes")
        XCTAssertEqual(active.notes, "Retry the same bytes")
    }

    func testTypingIsDebouncedAndFlushedBeforeSuspension() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, saveDebounce: .seconds(30))
        session.notes = "t"
        session.scheduleSave()
        session.notes = "ty"
        session.scheduleSave()
        XCTAssertTrue(session.history.isEmpty, "Keystrokes must not each write the archive")

        // flushPendingSave is the only thing that can have written this; the debounce is 30 s away.
        session.flushPendingSave()
        XCTAssertEqual(session.history.first?.notes, "ty")

        // .inactive is the last phase guaranteed to run before suspension, and it does not end in
        // background()'s unconditional save — so this asserts the flush itself.
        session.notes = "typed"
        session.scheduleSave()
        await session.handleScenePhase(.inactive)
        XCTAssertEqual(session.history.first?.notes, "typed", "Going inactive must flush pending typing")
        XCTAssertEqual(session.state, .idle, "Going inactive must not stop or save anything else")

        // With nothing pending, a flush writes nothing new.
        session.notes = "unsaved"
        session.flushPendingSave()
        XCTAssertEqual(session.history.first?.notes, "typed")
    }

    func testTheDebounceFiresOnItsOwnWhenTypingStops() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, saveDebounce: .milliseconds(120))
        session.notes = "typed"
        session.scheduleSave()
        XCTAssertTrue(session.history.isEmpty)
        for _ in 0..<100 where session.history.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(session.history.first?.notes, "typed")
    }
}
