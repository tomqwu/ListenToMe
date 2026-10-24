import XCTest
@testable import ListenToMeCore

final class MarkdownVaultTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let id = "1A2B3C4D-0000-4000-8000-000000000001"
    private let date = Date(timeIntervalSince1970: 1_792_766_100)   // 2026-10-23 14:35:00 UTC

    private func record(title: String = "Weekly sync", segments: [TranscriptSegment]? = nil,
                        transcript: String = "", summary: String = "Ship on Friday.",
                        notes: String? = "Bring the release checklist.", language: String? = nil,
                        languages: [String]? = nil) -> SessionRecord {
        SessionRecord(id: id, title: title, date: date, transcript: transcript, summary: summary,
                      segments: segments ?? [
                        TranscriptSegment(source: .others, text: "Can we ship Friday?", isFinal: true,
                                          start: 3, end: 6, speakerName: "Alice"),
                        TranscriptSegment(source: .you, text: "Yes, with the hotfix.", isFinal: true,
                                          start: 65, end: 70.5),
                        TranscriptSegment(source: .others, text: "Great.", isFinal: true,
                                          start: 71, end: 72, speakerName: "Alice")
                      ],
                      notes: notes, quickSuggestion: "", deepAnswer: nil,
                      attachments: [SessionAttachment(id: "a", name: "plan.pdf", storedName: "x", byteCount: 1)],
                      language: language, languages: languages)
    }

    func testSnapshotOfAFullNote() {
        let expected = """
        ---
        listentome_id: "1A2B3C4D-0000-4000-8000-000000000001"
        title: "Weekly sync"
        date: 2026-10-23T14:35:00Z
        duration: "01:09"
        language: "en-US"
        speakers:
          - "Alice"
          - "You"
        tags:
          - listentome
        ---

        # Weekly sync

        ## Summary

        Ship on Friday.

        ## Notes

        Bring the release checklist.

        ## Transcript

        - [00:03] **Alice:** Can we ship Friday?
        - [01:05] **You:** Yes, with the hotfix.
        - [01:11] **Alice:** Great.

        ## Attachments

        - plan.pdf

        """
        XCTAssertEqual(MarkdownVault.markdown(for: record(language: "en_US", languages: ["en_US"]), timeZone: utc),
                       expected)
    }

    /// Issue #206: the note describes the conversation's own languages, and lists them all after an
    /// Automatic switch; a record saved before #206 has no language rather than today's setting.
    func testFrontMatterUsesTheRecordsOwnLanguages() {
        let switched = MarkdownVault.markdown(for: record(language: "fr-FR", languages: ["en-US", "fr-FR"]),
                                              timeZone: utc)
        XCTAssertTrue(switched.contains("language: \"fr-FR\"\nlanguages:\n  - \"en-US\"\n  - \"fr-FR\"\nspeakers:"),
                      switched)
        let legacy = MarkdownVault.markdown(for: record(), timeZone: utc)
        XCTAssertFalse(legacy.contains("language"), legacy)
    }

    func testSnapshotOfALegacyRecordWithoutSegmentsOrLanguage() {
        let legacy = SessionRecord(id: id, title: "Old: \"notes\" #1", date: date,
                                   transcript: "You: hello\nOthers: hi", summary: "")
        let expected = """
        ---
        listentome_id: "1A2B3C4D-0000-4000-8000-000000000001"
        title: "Old: \\"notes\\" #1"
        date: 2026-10-23T14:35:00Z
        speakers: []
        tags:
          - listentome
        ---

        # Old: "notes" #1

        ## Transcript

        You: hello
        Others: hi

        """
        XCTAssertEqual(MarkdownVault.markdown(for: legacy, timeZone: utc), expected)
    }

    func testAllSummarySectionsAppearInOrderBeforeNotes() {
        let full = SessionRecord(id: id, title: "T", date: date, transcript: "", summary: "S",
                                 segments: [], notes: "N", quickSuggestion: "Q", deepAnswer: "D")
        let text = MarkdownVault.markdown(for: full, timeZone: utc)
        let order = ["## Summary\n\nS", "## Quick summary\n\nQ", "## Deep summary\n\nD", "## Notes\n\nN"]
            .map { text.range(of: $0)?.lowerBound }
        XCTAssertFalse(order.contains(nil), text)
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted())
        XCTAssertFalse(text.contains("## Transcript"), "an empty transcript is omitted")
        XCTAssertFalse(text.contains("duration:"))
    }

    func testUntimedSegmentsHaveNoTimestampsAndBlankLinesAreSkipped() {
        let segments = [
            TranscriptSegment(source: .you, text: "First\nline", isFinal: true, start: 0, end: 0),
            TranscriptSegment(source: .others, text: "  ", isFinal: true, start: 0, end: 0)
        ]
        let text = MarkdownVault.markdown(for: record(segments: segments), timeZone: utc)
        XCTAssertTrue(text.contains("## Transcript\n\n- **You:** First line\n"), text)
        XCTAssertTrue(text.contains("speakers:\n  - \"You\"\ntags:"), "a speaker with no words is not listed")
    }

    func testTitleWithNewlinesStaysOnOneLineAndYamlEscapesControlCharacters() {
        XCTAssertEqual(MarkdownVault.yaml("a\\b\t\"c\"\nd\r\u{07}"), "\"a\\\\b\\t\\\"c\\\"\\nd\"")
        let text = MarkdownVault.markdown(for: record(title: "Line one\nline two"), timeZone: utc)
        XCTAssertTrue(text.contains("# Line one line two\n"))
        XCTAssertTrue(text.contains("title: \"Line one line two\""))
    }

    func testTimestampsPastAnHour() {
        XCTAssertEqual(TranscriptTimestamp.clock(3_725.9), "1:02:05")
        XCTAssertEqual(TranscriptTimestamp.clock(-4), "00:00")
    }

    func testFileNameIsKeyedByIDAndStableAcrossTitleChanges() {
        let first = MarkdownVault.note(for: record(title: "New conversation"), timeZone: utc)
        let renamed = MarkdownVault.note(for: record(title: "Budget review"), timeZone: utc)
        XCTAssertEqual(first.fileName, "2026-10-23 1435 ListenToMe 1a2b3c4d.md")
        XCTAssertEqual(first.fileName, renamed.fileName)
        XCTAssertEqual(first.id, id)
        XCTAssertTrue(first.fileName.hasSuffix(MarkdownVault.marker(for: id)))
    }

    func testStartedAtFixesTheDateAndFileNameAcrossCheckpoints() {
        let moved = SessionRecord(id: id, title: "T", date: date.addingTimeInterval(3_600), transcript: "", summary: "")
        let note = MarkdownVault.note(for: moved, startedAt: date, timeZone: utc)
        XCTAssertEqual(note.fileName, "2026-10-23 1435 ListenToMe 1a2b3c4d.md")
        XCTAssertTrue(note.markdown.contains("date: 2026-10-23T14:35:00Z"), note.markdown)
    }

    func testOwnerIDIsReadOnlyFromTheFrontMatter() {
        XCTAssertEqual(MarkdownVault.ownerID(in: MarkdownVault.markdown(for: record(), timeZone: utc)), id)
        XCTAssertEqual(MarkdownVault.ownerID(in: "---\r\nlistentome_id: \"a\\\"b\\\\c\"\r\n---\r\n"), "a\"b\\c")
        XCTAssertEqual(MarkdownVault.ownerID(in: "---\nlistentome_id: plain-id\n---\n"), "plain-id")
        XCTAssertNil(MarkdownVault.ownerID(in: "# Notes\nlistentome_id: \"x\""), "not front matter")
        XCTAssertNil(MarkdownVault.ownerID(in: "---\ntitle: x\n---\nlistentome_id: \"x\""), "after the front matter")
        XCTAssertNil(MarkdownVault.ownerID(in: "---\nlistentome_id: \n"))
        XCTAssertNil(MarkdownVault.ownerID(in: "---\ntitle: unterminated\n"))
    }

    func testLongMarkersUseTheWholeID() {
        XCTAssertEqual(MarkdownVault.longMarker(for: id), "ListenToMe 1a2b3c4d000040008000000000000001.md")
        XCTAssertEqual(MarkdownVault.longMarker(for: "session-a").count, "ListenToMe .md".count + 16)
        XCTAssertNotEqual(MarkdownVault.longMarker(for: "session-a"), MarkdownVault.longMarker(for: "session-b"))
    }

    func testNonUUIDKeysAreHashedSoSharedPrefixesDiffer() {
        let a = MarkdownVault.key(for: "session-2026-a")
        let b = MarkdownVault.key(for: "session-2026-b")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 12)
        XCTAssertEqual(a, MarkdownVault.key(for: "session-2026-a"), "the key is stable")
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(MarkdownVault.key(for: "../x/y").count, 12, "path characters never reach the name")
    }
}
