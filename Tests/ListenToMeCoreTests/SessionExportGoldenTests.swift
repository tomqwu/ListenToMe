import XCTest
@testable import ListenToMeCore

/// Golden files for every export format (issue #130). The expected bytes live in `Golden/Export/`;
/// after an intended change, run `UPDATE_GOLDEN=1 swift test --filter SessionExportGoldenTests` and
/// review the diff of those files.
final class SessionExportGoldenTests: XCTestCase {
    static let utc = TimeZone(identifier: "UTC")!
    static let date = Date(timeIntervalSince1970: 1_792_766_100)   // 2026-10-23 14:35:00 UTC

    /// An iPhone/WhisperKit-style conversation: three speakers, lines past an hour, two short lines by
    /// one speaker that merge into a cue, a long line that splits, a zero-length line, characters WebVTT
    /// must escape, a speech correction, an Automatic switch (#206) and an attachment.
    static let timed = SessionRecord(
        id: "1A2B3C4D-0000-4000-8000-000000000001", title: "Weekly sync: Q4 <plan>", date: date,
        transcript: "", summary: "Ship on Friday.",
        segments: [
            TranscriptSegment(source: .others, text: "Can we ship Friday?", isFinal: true, start: 3, end: 5.2,
                              speakerID: "spk-1", speakerName: "Alice"),
            TranscriptSegment(source: .others, text: "Or is that too soon?", isFinal: true, start: 5.6, end: 6.9,
                              speakerID: "spk-1", speakerName: "Alice"),
            TranscriptSegment(source: .you, text: "Yes, with the hotfix & the <beta> flag.", isFinal: true,
                              start: 65.25, end: 70.5, originalText: "Yes with the hot fix and the beta flag",
                              correctionModel: "llama3.2"),
            TranscriptSegment(source: .others, text: "Then let's plan the rollout carefully: first the internal "
                              + "dogfood group on Monday, then ten percent of customers on Wednesday, and everyone "
                              + "else by Friday afternoon if the crash rate stays flat.", isFinal: true,
                              start: 3725.5, end: 3741, speakerID: "spk-1", speakerName: "Alice"),
            TranscriptSegment(source: .others, text: "Agreed.", isFinal: true, start: 3742, end: 3742,
                              speakerID: "spk-2", speakerName: "Bob")
        ],
        notes: "Bring the release checklist.", quickSuggestion: "Ask about the beta flag.",
        deepAnswer: "Plan the staged rollout.",
        attachments: [SessionAttachment(id: "a", name: "plan.pdf", storedName: "x", byteCount: 1)],
        language: "fr-FR", languages: ["en-US", "fr-FR"])

    /// A macOS SpeechAnalyzer conversation: lines carry no times until #68, and none are made up.
    static let untimed = SessionRecord(
        id: "untimed-1", title: "Conversation — Oct 23, 2026 at 2:35 PM", date: date, transcript: "",
        summary: "", segments: [
            TranscriptSegment(source: .you, text: "Hello there.", isFinal: true, start: 0, end: 0),
            TranscriptSegment(source: .others, text: "Hi!", isFinal: true, start: 0, end: 0)
        ], notes: "", language: "en-US", languages: ["en-US"])

    /// A record saved before lines were kept one by one, and before #206.
    static let legacy = SessionRecord(id: "legacy-1", title: "Old notes", date: date,
                                      transcript: "You: hello\nOthers: hi", summary: "Said hello.")

    private func assertGolden(_ actual: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let url = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
            .appendingPathComponent("Golden/Export/\(name)")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] != nil {
            XCTAssertNoThrow(try Data(actual.utf8).write(to: url), file: file, line: line)
            return
        }
        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            return XCTFail("Missing golden file \(name); run with UPDATE_GOLDEN=1", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, "\(name) differs from its golden file", file: file, line: line)
    }

    private func export(_ record: SessionRecord, _ format: SessionExportFormat) -> String {
        SessionExporter.export(record, as: format, timeZone: Self.utc)
    }

    func testTimedConversationInEveryFormat() {
        assertGolden(export(Self.timed, .markdown), "timed.md")
        assertGolden(export(Self.timed, .plainText), "timed.txt")
        assertGolden(export(Self.timed, .srt), "timed.srt")
        assertGolden(export(Self.timed, .webVTT), "timed.vtt")
        assertGolden(export(Self.timed, .json), "timed.json")
    }

    func testUntimedConversationHasNoTimesAndNoSubtitles() {
        assertGolden(export(Self.untimed, .markdown), "untimed.md")
        assertGolden(export(Self.untimed, .plainText), "untimed.txt")
        assertGolden(export(Self.untimed, .json), "untimed.json")
        XCTAssertEqual(export(Self.untimed, .srt), "")
        XCTAssertEqual(export(Self.untimed, .webVTT), "WEBVTT\n")
        XCTAssertEqual(SessionExporter.formats(for: Self.untimed), [.markdown, .plainText, .json])
        XCTAssertEqual(SessionExporter.formats(for: Self.timed), SessionExportFormat.allCases)
    }

    func testLegacyRecord() {
        assertGolden(export(Self.legacy, .markdown), "legacy.md")
        assertGolden(export(Self.legacy, .plainText), "legacy.txt")
        assertGolden(export(Self.legacy, .json), "legacy.json")
    }

    func testTimestampsCanBeLeftOut() {
        let markdown = SessionExporter.markdown(for: Self.timed, timestamps: false, timeZone: Self.utc)
        XCTAssertTrue(markdown.contains("- **Alice:** Can we ship Friday?"), markdown)
        XCTAssertFalse(markdown.contains("[00:03]"))
        let text = SessionExporter.export(Self.timed, as: .plainText, timestamps: false, timeZone: Self.utc)
        XCTAssertTrue(text.contains("\nAlice: Can we ship Friday?\n"), text)
    }

    func testJSONIsValidAndVersioned() throws {
        let object = try JSONSerialization.jsonObject(with: Data(export(Self.timed, .json).utf8)) as? [String: Any]
        XCTAssertEqual(object?["schema"] as? String, "listentome.conversation")
        XCTAssertEqual(object?["version"] as? Int, 1)
        XCTAssertEqual(object?["language"] as? String, "fr-FR")
        let legacy = try JSONSerialization.jsonObject(with: Data(export(Self.legacy, .json).utf8)) as? [String: Any]
        XCTAssertTrue(legacy?["language"] is NSNull, "an unknown language is null, never missing")
    }
}
