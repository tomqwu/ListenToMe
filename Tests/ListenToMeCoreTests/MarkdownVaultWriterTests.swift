import XCTest
@testable import ListenToMeCore

final class MarkdownVaultWriterTests: XCTestCase {
    private var root: URL!
    private var vault: URL!
    private let id = "1A2B3C4D-0000-4000-8000-000000000001"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        vault = root.appendingPathComponent("My Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func note(_ title: String, date: Date = Date(timeIntervalSince1970: 1_792_766_100)) -> MarkdownVaultNote {
        MarkdownVault.note(for: SessionRecord(id: id, title: title, date: date, transcript: "", summary: "S"),
                           timeZone: TimeZone(identifier: "UTC")!)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted()
    }

    func testWritesOneNoteAndUpdatesItInPlaceAfterARename() async throws {
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        let first = await writer.save(note("New conversation"))
        XCTAssertEqual(first, .saved(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
        // A later checkpoint with a newer date and a new title still updates the same note.
        let second = await writer.save(note("Budget review", date: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(second, .saved(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
        XCTAssertEqual(try files(), ["2026-10-23 1435 ListenToMe 1a2b3c4d.md"])
        let text = try String(contentsOf: vault.appendingPathComponent(try files()[0]), encoding: .utf8)
        XCTAssertTrue(text.contains("# Budget review"))
    }

    func testIdenticalContentIsNotRewrittenUnlessTheNoteWasDeleted() async throws {
        let writes = Counter()
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault)) { data, url in
            writes.increment()
            try MarkdownVaultWriter.coordinatedWrite(data, url)
        }
        _ = await writer.save(note("A"))
        let again = await writer.save(note("A"))
        XCTAssertEqual(again, .unchanged(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
        XCTAssertEqual(writes.value, 1)
        try FileManager.default.removeItem(at: vault.appendingPathComponent(try files()[0]))
        let restored = await writer.save(note("A"))
        XCTAssertEqual(restored, .saved(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
        XCTAssertEqual(writes.value, 2)
    }

    func testAReopenedAppFindsTheExistingNoteAndLeavesOtherFilesAlone() async throws {
        let unrelated = vault.appendingPathComponent("Weekly sync.md")
        try Data("mine".utf8).write(to: unrelated)
        let existing = vault.appendingPathComponent("2026-01-01 0900 ListenToMe 1a2b3c4d.md")
        let edited = "---\r\ntitle: \"Old\"\r\nlistentome_id: \"\(id)\"\r\n---\r\nedited in Obsidian"
        try Data(edited.utf8).write(to: existing)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        let outcome = await writer.save(note("A"))
        XCTAssertEqual(outcome, .saved(fileName: "2026-01-01 0900 ListenToMe 1a2b3c4d.md"))
        XCTAssertEqual(try files(), ["2026-01-01 0900 ListenToMe 1a2b3c4d.md", "Weekly sync.md"])
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "mine")
    }

    func testAFileWithTheShortNameButAnotherOwnerIsNeverOverwritten() async throws {
        // Another conversation whose ID shares the first eight hex digits, and a user's own note.
        let colliding = vault.appendingPathComponent("2026-01-01 0900 ListenToMe 1a2b3c4d.md")
        let otherRecord = SessionRecord(id: "1A2B3C4D-FFFF-4000-8000-000000000009", title: "Other",
                                        date: Date(), transcript: "", summary: "")
        let other = MarkdownVault.markdown(for: otherRecord)
        try Data(other.utf8).write(to: colliding)
        let foreign = vault.appendingPathComponent("Notes ListenToMe 1a2b3c4d.md")
        try Data("no front matter".utf8).write(to: foreign)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        let long = "2026-10-23 1435 ListenToMe 1a2b3c4d000040008000000000000001.md"
        let first = await writer.save(note("A"))
        XCTAssertEqual(first, .saved(fileName: long))
        XCTAssertEqual(try String(contentsOf: colliding, encoding: .utf8), other)
        XCTAssertEqual(try String(contentsOf: foreign, encoding: .utf8), "no front matter")
        // A new writer (a relaunch) finds the long name again by its front matter.
        let relaunched = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        let again = await relaunched.save(note("B"))
        XCTAssertEqual(again, .saved(fileName: long))
        XCTAssertEqual(try files().count, 3)
    }

    func testAVeryLongTitleStillUpdatesTheSameNoteAfterARelaunch() async throws {
        let title = String(repeating: "é long title ", count: 600)   // well past the 4 KB that is read
        _ = await MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault)).save(note(title))
        let relaunched = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        let again = await relaunched.save(note(title + "!"))
        XCTAssertEqual(again, .saved(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
        XCTAssertEqual(try files().count, 1)
    }

    func testAForeignFileWithTheLongNameIsAPerNoteFailure() async throws {
        try Data("mine".utf8).write(to: vault.appendingPathComponent("x ListenToMe 1a2b3c4d.md"))
        let longFile = vault.appendingPathComponent("y ListenToMe 1a2b3c4d000040008000000000000001.md")
        try Data("also mine".utf8).write(to: longFile)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .nameTaken)
        XCTAssertFalse(failure.stopsQueue)
        XCTAssertEqual(try String(contentsOf: longFile, encoding: .utf8), "also mine")
    }

    func testAnUnreadableExistingNoteIsNotOverwritten() async throws {
        // A folder with a note's name cannot be read as a note.
        let existing = vault.appendingPathComponent("2026-01-01 0900 ListenToMe 1a2b3c4d.md")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        guard case .failed = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(try files(), ["2026-01-01 0900 ListenToMe 1a2b3c4d.md"])
    }

    func testFolderFailuresStopTheQueueAndNoteFailuresDoNot() {
        let kinds: [(MarkdownVaultFailure.Kind, Bool)] = [
            (.folderMissing, true), (.accessDenied, true), (.diskFull, true),
            (.iCloudPending, false), (.nameTaken, false), (.other, false)
        ]
        for (kind, stops) in kinds {
            XCTAssertEqual(MarkdownVaultFailure(kind: kind, message: "").stopsQueue, stops, "\(kind)")
        }
    }

    func testAnICloudPlaceholderIsReportedNotOverwritten() async throws {
        let placeholder = vault.appendingPathComponent(".2026-01-01 0900 ListenToMe 1a2b3c4d.md.icloud")
        try Data().write(to: placeholder)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .iCloudPending)
        XCTAssertFalse(failure.needsNewFolder)
        XCTAssertTrue(failure.message.contains("2026-01-01 0900 ListenToMe 1a2b3c4d.md"), failure.message)
        XCTAssertEqual(try files(), [".2026-01-01 0900 ListenToMe 1a2b3c4d.md.icloud"])
    }

    func testADeletedFolderAsksForANewOne() async throws {
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        try FileManager.default.removeItem(at: vault)
        guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .folderMissing)
        XCTAssertTrue(failure.needsNewFolder)
    }

    func testARenamedFolderIsFollowed() async throws {
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        let renamed = root.appendingPathComponent("Renamed Vault", isDirectory: true)
        try FileManager.default.moveItem(at: vault, to: renamed)
        let outcome = await writer.save(note("A"))
        XCTAssertEqual(outcome, .saved(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: renamed.path),
                       ["2026-10-23 1435 ListenToMe 1a2b3c4d.md"])
    }

    func testAFolderMovedToTheTrashIsReportedMissing() async throws {
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault))
        try FileManager.default.moveItem(at: vault, to: trash.appendingPathComponent("My Vault"))
        guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .folderMissing)
    }

    func testAFileWhereTheFolderWasIsReportedMissing() async throws {
        let file = root.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: file))
        guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .folderMissing)
        XCTAssertTrue(failure.message.contains("“not-a-folder”"), failure.message)
    }

    func testAnUnreadableBookmarkAsksForANewFolder() async {
        let writer = MarkdownVaultWriter(bookmark: Data("not a bookmark".utf8))
        guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .folderMissing)
        XCTAssertNil(MarkdownVaultWriter.folderName(for: Data("not a bookmark".utf8)))
    }

    func testFolderNameComesFromTheBookmark() throws {
        let bookmark = try MarkdownVaultWriter.makeBookmark(for: vault)
        XCTAssertEqual(MarkdownVaultWriter.folderName(for: bookmark), "My Vault")
    }

    func testWriteErrorsBecomeVisibleFailures() async throws {
        let cases: [(Error, MarkdownVaultFailure.Kind)] = [
            (CocoaError(.fileWriteOutOfSpace), .diskFull),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .diskFull),
            (NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                     userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT))]),
             .diskFull),
            (CocoaError(.fileWriteNoPermission), .accessDenied),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)), .accessDenied),
            (CocoaError(.fileNoSuchFile), .folderMissing),
            (CocoaError(.fileWriteUnknown), .other)
        ]
        for (error, kind) in cases {
            let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault)) { _, _ in
                throw error
            }
            guard case .failed(let failure) = await writer.save(note("A")) else { return XCTFail("expected \(kind)") }
            XCTAssertEqual(failure.kind, kind, "\(error)")
            XCTAssertTrue(failure.message.contains("“My Vault”"), failure.message)
        }
        XCTAssertEqual(try files(), [], "a failed write leaves nothing behind")
    }

    func testAFailedWriteIsRetriedEvenWithIdenticalContent() async throws {
        let fail = Flag(true)
        let writer = MarkdownVaultWriter(bookmark: try MarkdownVaultWriter.makeBookmark(for: vault)) { data, url in
            if fail.value { throw CocoaError(.fileWriteOutOfSpace) }
            try MarkdownVaultWriter.coordinatedWrite(data, url)
        }
        guard case .failed = await writer.save(note("A")) else { return XCTFail("expected a failure") }
        fail.value = false
        let retried = await writer.save(note("A"))
        XCTAssertEqual(retried, .saved(fileName: "2026-10-23 1435 ListenToMe 1a2b3c4d.md"))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
