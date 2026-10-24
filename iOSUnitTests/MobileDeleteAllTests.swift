import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Delete all conversations (#220): everything a conversation owns goes, through the same path as
/// a single Delete; nothing runs while recording; the open conversation starts over.
@MainActor
final class MobileDeleteAllTests: XCTestCase {
    private var root: URL!
    private var inbox: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("deleteall-\(UUID().uuidString)")
        inbox = root.appendingPathComponent("SharedInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func makeSession() -> MobileSession {
        MobileSession(storageDirectory: root, sharedInbox: inbox)
    }

    /// A share folder as the share extension leaves it.
    @discardableResult
    private func share(_ id: String, folder name: String? = nil, text: String = "Shared text") throws -> URL {
        let folder = inbox.appendingPathComponent(name ?? id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(SharedImport(id: id, text: text, files: []))
            .write(to: folder.appendingPathComponent("manifest.json"))
        return folder
    }

    private func conversationFiles() -> [String] {
        let folder = root.appendingPathComponent("Conversations")
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.contains(".json") }
    }

    func testDeleteAllRemovesEveryConversationAndWhatItOwnsAndStartsOver() throws {
        let session = makeSession()
        session.notes = "First meeting"
        session.addAttachment(data: Data("Agenda".utf8), name: "agenda.txt")
        _ = try session.attachmentPresentationURL(for: XCTUnwrap(session.attachments.first))
        XCTAssertTrue(session.save())
        session.newConversation()
        session.notes = "Second meeting"
        XCTAssertTrue(session.save())
        // A share imported into a third conversation, whose inbox folder stayed behind (a crash
        // before it was removed). With its conversation gone it must not import again.
        let leftover = try share("batch-1")
        session.importSharedInbox()
        XCTAssertEqual(session.history.count, 3)
        try share("batch-1")
        // A share set aside as unimportable, a share not imported yet, and an unreadable history file.
        let failed = inbox.appendingPathComponent(MobileSession.failedInboxFolder).appendingPathComponent("old")
        try FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: root.appendingPathComponent("Conversations/broken.json"))
        session.reloadHistory()
        XCTAssertNotNil(session.archiveWarning)
        let attachments = root.appendingPathComponent("Attachments")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: attachments.path).isEmpty)
        let pending = try share("batch-2", text: "Arrived later")
        let deletedID = session.id

        XCTAssertTrue(session.canDeleteAllConversations)
        XCTAssertEqual(MobileSession.deleteAllTitle(count: session.history.count), "Delete all 3 conversations?")
        session.deleteAllConversations()

        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(conversationFiles(), [], "records and set-aside history files are gone")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: attachments.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: MobileSession.attachmentPresentationRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path), "a share not imported yet is kept")
        XCTAssertNotEqual(session.id, deletedID)
        XCTAssertEqual(session.title, "New conversation")
        XCTAssertFalse(session.hasContent)
        XCTAssertNil(session.archiveWarning)
        XCTAssertEqual(session.message, "3 conversations deleted from this device.")
        XCTAssertFalse(session.canDeleteAllConversations)

        let relaunched = MobileSession(storageDirectory: root, sharedInbox: root.appendingPathComponent("empty"))
        XCTAssertTrue(relaunched.history.isEmpty)
        XCTAssertFalse(relaunched.hasContent)
        relaunched.save()
        XCTAssertTrue(relaunched.history.isEmpty, "a deleted conversation never comes back")
    }

    func testDeleteAllWaitsForRecordingAndAIResponses() throws {
        let session = makeSession()
        XCTAssertFalse(session.canDeleteAllConversations, "nothing to delete")
        session.notes = "Keep me while busy"
        XCTAssertTrue(session.save())
        XCTAssertTrue(session.canDeleteAllConversations)
        for state in [MobileSession.State.preparing, .recording, .stopping] {
            session.state = state
            XCTAssertFalse(session.canDeleteAllConversations)
            session.deleteAllConversations()
            XCTAssertEqual(session.history.count, 1)
            XCTAssertEqual(session.notes, "Keep me while busy")
        }
        session.state = .idle
        session.isSummarizing = true
        session.deleteAllConversations()
        XCTAssertEqual(session.history.count, 1)
        session.isSummarizing = false
        session.deleteAllConversations()
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(session.message, "1 conversation deleted from this device.")
    }

    func testDeletingOneConversationAlsoRemovesItsLeftoverShare() throws {
        let session = makeSession()
        try share("batch-1")
        session.importSharedInbox()
        let imported = try XCTUnwrap(session.history.first)
        let leftover = try share("batch-1")
        let other = try share("batch-2", text: "Not imported yet")
        session.deleteConversation(id: imported.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertEqual(session.message, "Conversation and attachments deleted from this device.")
    }

    func testBothDeletesRunTheSameOwners() {
        let names = makeSession().conversationDataOwners.map(\.name)
        XCTAssertEqual(names, ["attachments", "Apple Watch audio", "shared imports", "Save to folder queue"])
    }

    func testConfirmationSaysWhatGoesAndWhatStays() {
        let plain = MobileSession.deleteAllMessage(vaultFolder: nil, watchWaiting: false)
        XCTAssertTrue(plain.hasPrefix("This removes every conversation's transcript, notes, attachments"))
        XCTAssertTrue(plain.hasSuffix("It cannot be undone."))
        XCTAssertFalse(plain.contains("folder"))
        let full = MobileSession.deleteAllMessage(vaultFolder: "Obsidian", watchWaiting: true)
        XCTAssertTrue(full.contains("Recordings still waiting from Apple Watch are kept."))
        XCTAssertTrue(full.contains("Notes already saved to “Obsidian” stay there"))
        XCTAssertEqual(MobileSession.deleteAllTitle(count: 1), "Delete 1 conversation?")
    }
}
