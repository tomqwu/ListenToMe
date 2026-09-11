import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileAttachmentTests: XCTestCase {
    func testSaveFailureKeepsAttachmentAvailableForRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        let active = root.appendingPathComponent("ActiveConversation.json")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        session.addAttachment(data: Data("Keep this original".utf8), name: "meeting.txt")
        let item = try XCTUnwrap(session.attachments.first)
        XCTAssertNotNil(session.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try session.attachmentStore().url(for: item).path))
        try FileManager.default.removeItem(at: active)
        XCTAssertTrue(session.save())
        XCTAssertEqual(MobileSession(storageDirectory: root).attachments, [item])
    }

    func testMalformedSharedBatchDoesNotReplaceCurrentConversation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox")
        let folder = inbox.appendingPathComponent("batch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let batch = SharedImport(id: "bad", text: "Must not replace current",
                                 files: [.init(name: "secret", storedName: "../outside")])
        try JSONEncoder().encode(batch).write(to: folder.appendingPathComponent("manifest.json"))
        let session = MobileSession(storageDirectory: root)
        session.notes = "Keep my meeting"; session.save()
        session.importSharedInbox(from: inbox)
        XCTAssertEqual(session.notes, "Keep my meeting")
        XCTAssertEqual(session.history.count, 1)
        XCTAssertTrue(session.message?.contains("Could not import") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testAttachmentImportTextPersistenceRemovalAndConversationDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.addAttachment(data: Data("Alex will prepare the checklist.".utf8), name: "meeting.txt")
        let attachment = try XCTUnwrap(session.attachments.first)
        let file = try session.attachmentStore().url(for: attachment)
        let presentation = try session.attachmentPresentationURL(for: attachment)
        XCTAssertEqual(presentation.lastPathComponent, "meeting.txt")
        XCTAssertEqual(try Data(contentsOf: presentation), try Data(contentsOf: file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(MobileSession(storageDirectory: root).attachments, [attachment])
        session.addAttachmentTextToNotes(attachment)
        XCTAssertTrue(session.notes.contains("Alex"))
        XCTAssertTrue(session.markdown.contains("meeting.txt"))
        session.removeAttachment(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: presentation.path))
        XCTAssertTrue(MobileSession(storageDirectory: root).attachments.isEmpty)
        session.addAttachment(data: Data([1, 2, 3]), name: "photo.jpg")
        _ = try session.attachmentPresentationURL(for: XCTUnwrap(session.attachments.first))
        let presentations = session.attachmentPresentationDirectory()
        let directory = session.attachmentStore().directory
        session.deleteConversation(id: session.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: presentations.path))
        XCTAssertTrue(MobileSession(storageDirectory: root).history.isEmpty)
    }

    func testRemovingOnlyAttachmentDoesNotRestoreStaleMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.addAttachment(data: Data([1]), name: "only.bin")
        session.removeAttachment(try XCTUnwrap(session.attachments.first))
        let restored = MobileSession(storageDirectory: root)
        XCTAssertTrue(restored.attachments.isEmpty)
        XCTAssertTrue(restored.history.allSatisfy { ($0.attachments ?? []).isEmpty })
    }

    func testSharedNotesImportIsIdempotentAndPreservesCurrentConversation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox")
        let batchFolder = inbox.appendingPathComponent("batch")
        try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
        let data = Data("Shared document".utf8)
        try data.write(to: batchFolder.appendingPathComponent("payload.txt"))
        let batch = SharedImport(id: "batch", text: "From Apple Notes", files: [.init(name: "note.txt", storedName: "payload.txt")])
        let manifest = try JSONEncoder().encode(batch)
        try manifest.write(to: batchFolder.appendingPathComponent("manifest.json"))
        let session = MobileSession(storageDirectory: root)
        session.notes = "Existing conversation"; session.save()
        session.importSharedInbox(from: inbox)
        XCTAssertEqual(session.notes, "From Apple Notes")
        XCTAssertEqual(session.attachments.count, 1)
        XCTAssertEqual(session.history.count, 2)
        XCTAssertTrue(session.history.contains { $0.notes == "Existing conversation" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: batchFolder.path))
        // Re-delivery after a crash must not create another conversation.
        try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
        try manifest.write(to: batchFolder.appendingPathComponent("manifest.json"))
        session.importSharedInbox(from: inbox)
        XCTAssertEqual(session.history.count, 2)
    }
}
