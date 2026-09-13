import XCTest
import SwiftUI
@testable import ListenToMeIOS

@MainActor
final class MobileMarkdownTests: XCTestCase {
    func testHeadingsBulletsAndInlineFormattingRenderWithoutSyntax() {
        let output = MarkdownText.inlineAttributed("### Decisions\n- **Alex** owns the *Friday* review.\n1. Check `status`.")
        XCTAssertEqual(String(output.characters), "Decisions\n•  Alex owns the Friday review.\n1. Check status.")
        XCTAssertTrue(output.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(output.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        XCTAssertTrue(output.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    func testCodeAndPartialStreamKeepTheirContents() {
        XCTAssertEqual(MarkdownText.blocks("## Review\n```swift\nlet count = 2\n```\n**Done**"),
                       [.markdown("## Review"), .code("let count = 2"), .markdown("**Done**")])
        XCTAssertEqual(MarkdownText.blocks("```swift\nlet count ="), [.code("let count =")])
        XCTAssertTrue(String(MarkdownText.inlineAttributed("- **Decision").characters).contains("Decision"))
    }

    func testReadableShareRemovesMarkupButPreservesCodeLinksAndSavedContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.title = "Planning"
        session.notes = "## Decision\n- **Alex** owns *Friday*.\n[Checklist](https://example.com/check)\n```swift\nlet tag = \"#literal\"\n```"
        session.quickSummary = "- **Alex** confirms Friday."
        XCTAssertTrue(session.save())
        let text = session.readableShareText
        XCTAssertFalse(text.contains("## Decision"))
        XCTAssertFalse(text.contains("**Alex**"))
        XCTAssertFalse(text.contains("```"))
        XCTAssertTrue(text.contains("Alex owns Friday."))
        XCTAssertTrue(text.contains("https://example.com/check"))
        XCTAssertTrue(text.contains("let tag = \"#literal\""))
        XCTAssertEqual(text, MobileSession.readableShareText(for: try XCTUnwrap(session.history.first)))
        XCTAssertTrue(session.markdown.contains("**Alex**"), "Markdown export remains available")
    }

    func testRenderingDoesNotChangeSavedOrExportedMarkdown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        let markdown = "### Decisions\n- **Alex** will review on Friday."
        session.summary = markdown; session.quickSummary = markdown; session.deepThought = markdown
        _ = MarkdownText.inlineAttributed(markdown)
        XCTAssertTrue(session.save())
        let restored = MobileSession(storageDirectory: root)
        for mode in MobileSummaryMode.allCases { XCTAssertEqual(restored.output(for: mode), markdown) }
        XCTAssertEqual(restored.markdown.components(separatedBy: markdown).count - 1, 3)
    }
}
