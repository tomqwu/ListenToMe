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

    func testTypingIsDebouncedAndFlushedWhenTheAppLeavesTheForeground() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, saveDebounce: .milliseconds(120))
        session.notes = "t"
        session.scheduleSave()
        session.notes = "ty"
        session.scheduleSave()
        XCTAssertTrue(session.history.isEmpty, "Keystrokes must not each write the archive")

        for _ in 0..<100 where session.history.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(session.history.first?.notes, "ty")

        session.notes = "typed"
        session.scheduleSave()
        await session.handleScenePhase(.background)
        XCTAssertEqual(session.history.first?.notes, "typed", "Backgrounding must flush pending typing")
    }
}
