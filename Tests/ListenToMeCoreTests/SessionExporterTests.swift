import XCTest
@testable import ListenToMeCore

final class SessionExporterTests: XCTestCase {
    private let transcript = [
        TranscriptSegment(source: .others, text: "Can you ship Friday?", isFinal: true, start: 0, end: 0),
        TranscriptSegment(source: .you, text: "Yes, with the hotfix.", isFinal: true, start: 0, end: 0)
    ]

    func testManualEditsExportManualProvenanceAndKeepFirstOriginal() {
        for priorModel in [nil, "llama3.2"] as [String?] {
            let original = TranscriptSegment(source: .others, text: "The budget is $120.", isFinal: true,
                start: 34, end: 36, speakerID: "speaker-1", speakerName: "Sam",
                originalText: priorModel == nil ? nil : "The budget is 120.", correctionModel: priorModel)
            let store = ConversationStore()
            store.apply(original)
            for corrected in ["The budget is $125.", "The budget is $130."] {
                XCTAssertTrue(store.edit(id: original.id, text: corrected))
                let beforeExport = store.utterances
                let markdown = SessionExporter.markdown(title: "Budget", transcript: store.utterances)
                let firstWording = original.originalText ?? original.text
                XCTAssertTrue(markdown.contains("- Original: \(firstWording)\n  Manual correction: \(corrected)"),
                              markdown)
                XCTAssertFalse(markdown.contains("AI correction:"), markdown)
                XCTAssertEqual(store.utterances, beforeExport)
                XCTAssertEqual(store.utterances.first?.id, original.id)
                XCTAssertEqual(store.utterances.first?.start, original.start)
                XCTAssertEqual(store.utterances.first?.speakerID, original.speakerID)
                XCTAssertEqual(store.utterances.first?.originalText, firstWording)
                XCTAssertEqual(store.utterances.first?.correctionModel, "Manual")
            }
        }
    }

    func testKnownModelCorrectionRetainsAIAttribution() {
        let segment = TranscriptSegment(source: .others, text: "The budget is $120.", isFinal: true,
            start: 34, end: 36, originalText: "The budget is 120.", correctionModel: "llama3.2")
        let markdown = SessionExporter.markdown(title: "Budget", transcript: [segment])
        XCTAssertTrue(markdown.contains("- Original: The budget is 120.\n  AI correction: The budget is $120."),
                      markdown)
        XCTAssertFalse(markdown.contains("Manual correction:"), markdown)
        XCTAssertEqual(segment.originalText, "The budget is 120.")
        XCTAssertEqual(segment.correctionModel, "llama3.2")
    }

    func testLegacyUnknownCorrectionStaysNeutralAndUncorrectedLinesHaveNoEntry() {
        for model in [nil, "", " \n "] as [String?] {
            let segment = TranscriptSegment(source: .others, text: "The budget is $120.", isFinal: true,
                start: 34, end: 36, originalText: "The budget is 120.", correctionModel: model)
            let markdown = SessionExporter.markdown(title: "Budget", transcript: [segment])
            XCTAssertTrue(markdown.contains("- Original: The budget is 120.\n  Correction: The budget is $120."),
                          markdown)
            XCTAssertFalse(markdown.contains("AI correction:"), markdown)
            XCTAssertFalse(markdown.contains("Manual correction:"), markdown)
            XCTAssertEqual(segment.correctionModel, model)
        }
        let uncorrected = TranscriptSegment(source: .others, text: "Unchanged", isFinal: true,
            start: 0, end: 1, correctionModel: "Manual")
        let markdown = SessionExporter.markdown(title: "Budget", transcript: [uncorrected])
        XCTAssertTrue(markdown.contains("Others:** Unchanged"), markdown)
        XCTAssertFalse(markdown.contains("Speech corrections"), markdown)
    }

    func testTranscriptNamesAndCorrectionTextCannotInjectMarkdown() {
        let segment = TranscriptSegment(source: .others, text: "Please **ship**\n# Notes\n- now",
                                        isFinal: true, start: 0, end: 1, speakerID: "ann",
                                        speakerName: "Ann**\n# Owner",
                                        originalText: "Original [link](https://example.com)\n> quoted")
        let markdown = SessionExporter.markdown(title: "Meeting", transcript: [segment],
                                               listenerSummary: "**Keep bold**")
        XCTAssertTrue(markdown.contains(##"Ann\*\* \# Owner"##), markdown)
        XCTAssertTrue(markdown.contains(##"Please \*\*ship\*\* \# Notes \- now"##), markdown)
        XCTAssertTrue(markdown.contains(##"Original \[link\](https://example.com) \> quoted"##), markdown)
        XCTAssertFalse(markdown.contains("\n# Notes"))
        XCTAssertTrue(markdown.contains("**Keep bold**"), "AI Markdown must retain formatting")
    }

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

    func testRecapIncludesTitle() {
        let recap = SessionExporter.recap(title: "Recap A")
        XCTAssertTrue(recap.hasPrefix("# Recap A"))
    }

    func testRecapIncludesPopulatedSections() {
        let recap = SessionExporter.recap(
            title: "S", listenerSummary: "Discussing the release",
            quickSuggestion: "Say yes", deepAnswer: "Detailed plan")
        XCTAssertTrue(recap.contains("## Summary\n\nDiscussing the release"))
        XCTAssertTrue(recap.contains("## Quick suggestion\n\nSay yes"))
        XCTAssertTrue(recap.contains("## Deep answer\n\nDetailed plan"))
    }

    func testRecapOmitsEmptySections() {
        let recap = SessionExporter.recap(title: "S", listenerSummary: "Only summary")
        XCTAssertTrue(recap.contains("## Summary"))
        XCTAssertFalse(recap.contains("## Quick suggestion"))
        XCTAssertFalse(recap.contains("## Deep answer"))
    }

    func testRecapWhitespaceOnlySectionsOmitted() {
        let recap = SessionExporter.recap(title: "S", listenerSummary: "   \n  ")
        XCTAssertFalse(recap.contains("## Summary"))
    }

    func testRecapExcludesTranscript() {
        let md = SessionExporter.markdown(
            title: "S", transcript: transcript, listenerSummary: "Discussing the release")
        let recap = SessionExporter.recap(title: "S", listenerSummary: "Discussing the release")
        // The full markdown carries the transcript; the recap must not.
        XCTAssertTrue(md.contains("- **Others:** Can you ship Friday?"))
        XCTAssertFalse(recap.contains("## Transcript"))
        XCTAssertFalse(recap.contains("- **Others:** Can you ship Friday?"))
        XCTAssertFalse(recap.contains("- **You:** Yes, with the hotfix."))
    }

    /// Issue #130: lines their engine timed carry `[mm:ss]`; a line without a time in the same
    /// conversation gets none rather than an invented `[00:00]`.
    func testTimedLinesCarryTimestampsAndUntimedOnesDoNot() {
        let mixed = [
            TranscriptSegment(source: .others, text: "Timed", isFinal: true, start: 75, end: 78),
            TranscriptSegment(source: .you, text: "Typed", isFinal: true, start: 0, end: 0)
        ]
        let md = SessionExporter.markdown(title: "S", transcript: mixed)
        XCTAssertTrue(md.contains("- [01:15] **Others:** Timed\n- **You:** Typed"), md)
        XCTAssertFalse(SessionExporter.markdown(title: "S", transcript: mixed, timestamps: false).contains("[01:15]"))
    }
}
