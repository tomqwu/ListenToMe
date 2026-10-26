import XCTest
@testable import ListenToMeCore

final class ReferenceRenderingTests: XCTestCase {
    func testHeadingsTrimTrailingWhitespaceBeforeAddingEmphasis() {
        XCTAssertEqual(InlineMarkdownPreprocessor.preprocess("## Action Items \t\n### \t\n- Ship"),
                       "**Action Items**\n\n•  Ship")
        XCTAssertEqual(InlineMarkdownPreprocessor.preprocess("    ## Code \n  ## Heading \t"),
                       "    ## Code \n  **Heading**")
        XCTAssertEqual(InlineMarkdownPreprocessor.preprocess("**existing**\nPlain text"), "**existing**\nPlain text")
    }

    func testDirectSymlinksCannotBypassReferenceSizeLimits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let large = root.appendingPathComponent("large.txt"), link = root.appendingPathComponent("latest.txt")
        try Data(repeating: 65, count: 200_001).write(to: large)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: large)
        let result = FileContextLoader.load([link, large])
        XCTAssertTrue(result.documents.isEmpty)
        XCTAssertEqual(result.skipped.map(\.reason), ["symbolic link", "larger than 200 KB"])
    }

    func testDirectDirectorySymlinkIsSkippedAndRealTextRemainsReadable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("folder"), link = root.appendingPathComponent("shortcut")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "Agenda".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let result = FileContextLoader.load([link, folder])
        XCTAssertEqual(result.documents.map(\.content), ["Agenda"])
        XCTAssertEqual(result.skipped.map(\.reason), ["symbolic link"])
    }
}
