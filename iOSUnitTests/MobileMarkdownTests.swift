import XCTest
import SwiftUI
@testable import ListenToMeIOS
import ListenToMeCore

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

    func testShareSendsOnlyTheChosenSummaryReadablyAndNeverTheTranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.title = "Planning"
        session.notes = "Private aside"
        session.quickSummary = "- **Alex** confirms Friday."
        session.summary = "### Decisions\n- Ship the *beta*."
        session.segments = [TranscriptSegment(source: .you, text: "Live words nobody shares", isFinal: true, start: 0, end: 2)]
        let record = session.currentRecord
        XCTAssertEqual(session.shareContents(for: record), [.fullSummary, .quickSummary],
                       "Audio is offered only when this conversation's audio is saved")
        func text(_ content: ConversationShareContent) throws -> String {
            try XCTUnwrap(session.sharePayload(content, for: record)?.items.first as? String)
        }
        let quick = try text(.quickSummary)
        XCTAssertTrue(quick.contains("Planning") && quick.contains("Alex confirms Friday."), quick)
        XCTAssertFalse(quick.contains("**") || quick.contains("Ship the") || quick.contains("Private aside"), quick)
        let full = try text(.fullSummary)
        XCTAssertTrue(full.contains("Ship the beta."), full)
        XCTAssertFalse(full.contains("###") || full.contains("confirms Friday") || full.contains("Private aside"), full)
        XCTAssertEqual(try XCTUnwrap(session.defaultSharePayload(for: record)?.items.first as? String), full,
                       "a plain Share sends the full summary")
        XCTAssertFalse(quick.contains("Live words") || full.contains("Live words"), "the transcript is never shared")
        XCTAssertNil(session.sharePayload(.audio, for: record))
    }

    func testRenderingDoesNotChangeSavedOrExportedMarkdown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        let markdown = "### Decisions\n- **Alex** will review on Friday."
        session.summary = markdown; session.quickSummary = markdown; session.earlierDeepAnalysis = markdown
        _ = MarkdownText.inlineAttributed(markdown)
        XCTAssertTrue(session.save())
        let restored = MobileSession(storageDirectory: root)
        for mode in MobileSummaryMode.allCases { XCTAssertEqual(restored.output(for: mode), markdown) }
        XCTAssertEqual(restored.markdown.components(separatedBy: markdown).count - 1, 3)
    }
}
