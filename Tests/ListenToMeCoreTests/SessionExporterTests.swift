import XCTest
@testable import ListenToMeCore

final class SessionExporterTests: XCTestCase {
    private let transcript = [
        TranscriptSegment(source: .others, text: "Can you ship Friday?", isFinal: true, start: 0, end: 1),
        TranscriptSegment(source: .you, text: "Yes, with the hotfix.", isFinal: true, start: 1, end: 2)
    ]

    func testIncludesTitleAndSpeakerLabeledTranscript() {
        let md = SessionExporter.markdown(title: "Session A", transcript: transcript)
        XCTAssertTrue(md.hasPrefix("# Session A"))
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("- **Others:** Can you ship Friday?"))
        XCTAssertTrue(md.contains("- **You:** Yes, with the hotfix."))
    }

    func testOmitsEmptyOptionalSections() {
        let md = SessionExporter.markdown(title: "S", transcript: transcript)
        XCTAssertFalse(md.contains("## Context notes"))
        XCTAssertFalse(md.contains("## Listener summary"))
        XCTAssertFalse(md.contains("## Quick suggestion"))
        XCTAssertFalse(md.contains("## Deep answer"))
    }

    func testIncludesPopulatedSections() {
        let md = SessionExporter.markdown(
            title: "S", transcript: transcript, notes: "I am backend lead",
            listenerSummary: "Discussing the release", quickSuggestion: "Say yes",
            deepAnswer: "Detailed plan")
        XCTAssertTrue(md.contains("## Context notes\n\nI am backend lead"))
        XCTAssertTrue(md.contains("## Listener summary\n\nDiscussing the release"))
        XCTAssertTrue(md.contains("## Quick suggestion\n\nSay yes"))
        XCTAssertTrue(md.contains("## Deep answer\n\nDetailed plan"))
    }

    func testWhitespaceOnlySectionsOmitted() {
        let md = SessionExporter.markdown(title: "S", transcript: transcript, notes: "   \n  ")
        XCTAssertFalse(md.contains("## Context notes"))
    }

    func testEmptyTranscriptShowsPlaceholder() {
        let md = SessionExporter.markdown(title: "S", transcript: [])
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("_(no transcript captured)_"))
    }
}
