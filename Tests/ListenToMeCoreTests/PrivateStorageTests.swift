import XCTest
@testable import ListenToMeCore

final class PrivateStorageTests: XCTestCase {
    private func temporary() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testWritesAreAtomicAndProtectedWhereThePlatformHasDataProtection() {
        XCTAssertTrue(PrivateStorage.writingOptions.contains(.atomic))
        #if os(iOS)
        XCTAssertTrue(PrivateStorage.writingOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
        XCTAssertEqual(PrivateStorage.directoryAttributes[.protectionKey] as? FileProtectionType,
                       .completeUntilFirstUserAuthentication)
        #else
        XCTAssertEqual(PrivateStorage.writingOptions, [.atomic])
        XCTAssertTrue(PrivateStorage.directoryAttributes.isEmpty)
        #endif
    }

    func testBackupExclusionIsSetClearedAndIgnoredForMissingPaths() throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(PrivateStorage.isExcludedFromBackup(directory))
        XCTAssertNoThrow(try PrivateStorage.setExcludedFromBackup(true, at: directory),
                         "A directory that does not exist yet is not an error")
        try PrivateStorage.createDirectory(at: directory)
        XCTAssertFalse(PrivateStorage.isExcludedFromBackup(directory))
        try PrivateStorage.setExcludedFromBackup(true, at: directory)
        XCTAssertTrue(settles(to: true, directory))
        try PrivateStorage.setExcludedFromBackup(false, at: directory)
        XCTAssertTrue(settles(to: false, directory))
    }

    /// macOS can apply a backup-exclusion change a few milliseconds after `setResourceValues`
    /// returns (seen once NaturalLanguage is loaded in the same process, #57), so the read waits
    /// briefly for the flag to settle instead of racing it.
    private func settles(to expected: Bool, _ url: URL, within seconds: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while PrivateStorage.isExcludedFromBackup(url) != expected {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return true
    }

    func testArchivedConversationsAndAttachmentsAreWrittenThroughPrivateStorage() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root.appendingPathComponent("Conversations"))
        try archive.save(SessionRecord(id: "abc", title: "Pay review", date: Date(),
                                       transcript: "Microphone: hello", summary: ""))
        XCTAssertEqual(try archive.all().map(\.id), ["abc"])
        let store = SessionAttachmentStore(directory: root.appendingPathComponent("Attachments"))
        let attachment = try store.add(data: Data("photo".utf8), name: "board.txt")
        XCTAssertEqual(try Data(contentsOf: try store.url(for: attachment)), Data("photo".utf8))
    }
}
