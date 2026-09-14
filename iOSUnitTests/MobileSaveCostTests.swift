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
