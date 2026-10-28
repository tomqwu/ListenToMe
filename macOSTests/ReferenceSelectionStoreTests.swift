import Foundation
import XCTest
import ListenToMeCore

final class ReferenceSelectionStoreTests: XCTestCase {
    func testReadableLegacyReferenceStillLoadsWithoutCreatingAGrant() throws {
        let suite = "legacy-reference-scope-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".txt")
        try "legacy reference".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        defaults.set([file.path], forKey: "referencePaths")
        let restored = ReferenceSelectionStore(defaults: defaults).restore()
        XCTAssertEqual(restored.urls, [file])
        XCTAssertTrue(restored.skipped.isEmpty)
        XCTAssertEqual(FileContextLoader.load(restored.urls).documents.first?.content, "legacy reference")
        XCTAssertNil(defaults.dictionary(forKey: "referenceBookmarks"))
    }

    func testBrokenReferenceGrantRequiresReselectionInsteadOfReadingThePath() throws {
        let suite = "broken-reference-scope-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".txt")
        try "This readable file must not be used through a corrupt grant".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let path = file.path
        defaults.set([path], forKey: "referencePaths")
        defaults.set([path: Data([1, 2, 3])], forKey: "referenceBookmarks")
        let restored = ReferenceSelectionStore(defaults: defaults).restore()
        XCTAssertTrue(restored.urls.isEmpty)
        XCTAssertEqual(restored.skipped.count, 1)
        XCTAssertTrue(restored.skipped.first?.reason.contains("choose file or folder again") == true)
    }

    func testFileAndDirectoryReferencesRestoreNativeScopesAndContent() throws {
        let suite = "reference-scope-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chosen.txt")
        let folder = root.appendingPathComponent("chosen-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try "selected file content".write(to: file, atomically: true, encoding: .utf8)
        try "selected folder content".write(to: folder.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(ReferenceSelectionStore(defaults: defaults).save([file, folder]).isEmpty)
        let persisted = defaults.dictionary(forKey: "referenceBookmarks") as? [String: Data] ?? [:]
        XCTAssertEqual(Set(persisted.keys), Set([file.path, folder.path]))
        for chosen in [file, folder] {
            let bookmark = try XCTUnwrap(persisted[chosen.path])
            var stale = false
            let scoped = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
            let acquired = scoped.startAccessingSecurityScopedResource()
            XCTAssertTrue(acquired, "Persisted data must resolve with the native security-scope option")
            if acquired { scoped.stopAccessingSecurityScopedResource() }
        }
        let restored = ReferenceSelectionStore(defaults: defaults).restore()
        XCTAssertEqual(restored.urls.count, 2)
        XCTAssertTrue(restored.skipped.isEmpty)
        for url in restored.urls {
            let acquired = url.startAccessingSecurityScopedResource()
            XCTAssertTrue(acquired, "Restored reference must carry a persisted native scope")
            if acquired { url.stopAccessingSecurityScopedResource() }
        }
        let loaded = FileContextLoader.load(restored.urls)
        XCTAssertEqual(Set(loaded.documents.map(\.content)), ["selected file content", "selected folder content"])
        XCTAssertTrue(loaded.skipped.isEmpty)
        ReferenceSelectionStore(defaults: defaults).save([])
        XCTAssertTrue(ReferenceSelectionStore(defaults: defaults).restore().urls.isEmpty)
        XCTAssertTrue((defaults.dictionary(forKey: "referenceBookmarks") ?? [:]).isEmpty)
    }
}
