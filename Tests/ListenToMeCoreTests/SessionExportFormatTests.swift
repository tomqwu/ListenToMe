import XCTest
@testable import ListenToMeCore

/// Subtitle cue rules, file names, timestamps and per-conversation languages behind the exports
/// (issues #130 and #206). The full documents are covered by `SessionExportGoldenTests`.
final class SessionExportFormatTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_792_766_100)   // 2026-10-23 14:35:00 UTC

    private func line(_ text: String, _ start: TimeInterval, _ end: TimeInterval, speaker: String? = nil,
                      source: SpeakerSource = .others) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true, start: start, end: end, speakerName: speaker)
    }

    private func record(_ segments: [TranscriptSegment]?, title: String = "T") -> SessionRecord {
        SessionRecord(id: "r", title: title, date: date, transcript: "", summary: "", segments: segments)
    }

    // MARK: Timestamps

    func testSubtitleTimesPastAnHourAndRounding() {
        XCTAssertEqual(TranscriptTimestamp.subtitle(3725.5, separator: ","), "01:02:05,500")
        XCTAssertEqual(TranscriptTimestamp.subtitle(6000.0004, separator: "."), "01:40:00.000")
        XCTAssertEqual(TranscriptTimestamp.subtitle(36_000 * 10, separator: ","), "100:00:00,000")
        XCTAssertEqual(TranscriptTimestamp.subtitle(-1, separator: "."), "00:00:00.000")
        XCTAssertEqual(TranscriptTimestamp.subtitle(0.9996, separator: "."), "00:00:01.000")
    }

    func testOnlyEngineTimedLinesCount() {
        XCTAssertFalse(TranscriptTimestamp.isTimed(line("a", 0, 0)))
        XCTAssertTrue(TranscriptTimestamp.isTimed(line("a", 0, 1.5)), "WhisperKit's first line starts at 0")
        XCTAssertNil(TranscriptTimestamp.duration(of: [line("a", 0, 0)]))
        XCTAssertEqual(TranscriptTimestamp.duration(of: [line("a", 0, 0), line("b", 2, 5), line("c", 9, 12)]), 10)
    }

    // MARK: Cues

    func testOneSpeakerHasNoNamesAndUntimedLinesAreSkipped() {
        let srt = SessionExporter.srt(for: record([line("Hello.", 1, 2, speaker: "Me"), line("Lost.", 0, 0),
                                                   line("  ", 3, 4, speaker: "Me")]))
        XCTAssertEqual(srt, "1\n00:00:01,000 --> 00:00:02,000\nHello.\n")
        XCTAssertEqual(SessionExporter.webVTT(for: record([line("Hi <b>", 1, 2)])),
                       "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi &lt;b&gt;\n")
    }

    func testCuesAreSortedAndDifferentSpeakersMayOverlap() {
        let cues = SessionExporter.cues(for: [line("Second", 5, 7, speaker: "B"), line("First", 4, 8, speaker: "A")])
        XCTAssertEqual(cues.map(\.text), ["First", "Second"])
        XCTAssertEqual(cues.map(\.end), [8, 7])
    }

    func testSameSpeakerLinesMergeOnlyWhenCloseShortAndBrief() {
        let close = SessionExporter.cues(for: [line("One.", 1, 2, speaker: "A"), line("Two.", 2.5, 3, speaker: "A")])
        XCTAssertEqual(close.map(\.text), ["One. Two."])
        let apart = SessionExporter.cues(for: [line("One.", 1, 2, speaker: "A"), line("Two.", 4, 5, speaker: "A")])
        XCTAssertEqual(apart.count, 2, "a gap over a second starts a new cue")
        let others = SessionExporter.cues(for: [line("One.", 1, 2, speaker: "A"), line("Two.", 2.2, 3, speaker: "B")])
        XCTAssertEqual(others.count, 2)
        let long = SessionExporter.cues(for: [line("One.", 1, 2, speaker: "A"), line("Two.", 2.5, 9, speaker: "A")])
        XCTAssertEqual(long.count, 2, "a merged cue may not last longer than seven seconds")
    }

    func testLongSilentLineIsSplitByTimeAndTextNeverHoldsAnArrow() {
        let cues = SessionExporter.cues(for: [line("a b c d", 0, 21)])
        XCTAssertEqual(cues.count, 3, cues.map(\.text).joined(separator: "|"))
        XCTAssertEqual(cues.first?.start, 0)
        XCTAssertEqual(cues.last?.end, 21)
        XCTAssertEqual(SessionExporter.cues(for: [line("word", 0, 30)]).count, 1, "one word cannot be split")
        XCTAssertTrue(SessionExporter.srt(for: record([line("a --> b", 1, 2)])).contains("a -> b"))
    }

    func testUnspacedScriptsSplitAndWrapAtCharacters() {
        let chinese = String(repeating: "我们星期五发布新版本", count: 5)   // 50 characters
        let cues = SessionExporter.cues(for: [line(chinese, 0, 5)])
        XCTAssertEqual(cues.count, 2)
        XCTAssertTrue(cues.allSatisfy { $0.text.count <= SessionExporter.maximumUnspacedCueCharacters })
        XCTAssertEqual(SessionExporter.wrap(String(chinese.prefix(30))).map(\.count), [15, 15])
        XCTAssertEqual(SessionExporter.wrap(chinese).map(\.count), [16, 16, 16, 2])
        let merged = SessionExporter.cues(for: [line("你好", 0, 1, speaker: "A"), line("再见", 1.2, 2, speaker: "A")])
        XCTAssertEqual(merged.map(\.text), ["你好再见"], "no space is added between unspaced lines")
        XCTAssertFalse(SessionExporter.isUnspaced("Great."))
    }

    func testWrapFallsBackToGreedyLinesWhenNoBalancedSplitFits() {
        let text = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa b c"   // a 45-character word
        XCTAssertEqual(SessionExporter.wrap(text), ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "b c"])
        XCTAssertEqual(SessionExporter.chunks("single", into: 3), ["single"])
    }

    // MARK: File names

    func testFileNameComesFromTitleAndDate() {
        XCTAssertEqual(SessionExporter.fileName(title: "Weekly sync", date: date, fileExtension: "srt", timeZone: utc),
                       "Weekly sync 2026-10-23 1435.srt")
        XCTAssertEqual(SessionExporter.fileName(title: "Q4: plan / budget?\n\"final\"", date: date,
                                                fileExtension: "md", suffix: "recap", timeZone: utc),
                       "Q4 plan budget final 2026-10-23 1435 recap.md")
        XCTAssertEqual(SessionExporter.fileName(for: record(nil, title: "Réunion d’équipe"), format: .json,
                                                timeZone: utc), "Réunion d’équipe 2026-10-23 1435.json")
    }

    func testGeneratedEmptyAndHiddenTitlesAreSafe() {
        XCTAssertEqual(SessionExporter.safeTitle(ConversationTitle.generated("Oct 23, 2026")), "Conversation")
        XCTAssertEqual(SessionExporter.safeTitle("New conversation"), "Conversation")
        XCTAssertEqual(SessionExporter.safeTitle("  ///  "), "Conversation")
        XCTAssertEqual(SessionExporter.safeTitle("..hidden."), "hidden")
        XCTAssertEqual(SessionExporter.safeTitle("-rf notes"), "rf notes")
        let long = SessionExporter.safeTitle(String(repeating: "word ", count: 40))
        XCTAssertLessThanOrEqual(long.count, SessionExporter.maximumTitleLength)
        XCTAssertFalse(long.hasSuffix(" "))
    }

    func testFormatMetadata() {
        XCTAssertEqual(SessionExportFormat.allCases.map(\.fileExtension), ["md", "txt", "srt", "vtt", "json"])
        XCTAssertEqual(SessionExportFormat.webVTT.title, "Subtitles (WebVTT)")
        XCTAssertEqual(SessionExportFormat.plainText.id, "plainText")
        XCTAssertEqual(SessionExportFormat.allCases.filter(\.needsTimestamps), [.srt, .webVTT])
        XCTAssertEqual(SessionExporter.recap(for: SessionRecord(id: "r", title: "T", date: date, transcript: "",
                                                                summary: "S")), "# T\n\n## Summary\n\nS\n")
    }

    // MARK: Languages (#206)

    func testLanguagesNormaliseAndKeepFirstUseOrder() {
        var languages = ConversationLanguages()
        XCTAssertTrue(languages.isEmpty)
        languages.record("en_US")
        languages.record("fr-FR")
        languages.record("en-US")
        languages.record("  ")
        XCTAssertEqual(languages.all, ["en-US", "fr-FR"])
        XCTAssertEqual(languages.current, "en-US")
        XCTAssertEqual(ConversationLanguages(current: "de_DE", all: ["en_US"]).all, ["en-US", "de-DE"])
    }

    func testReplacementForAWholeReTranscriptionAndUndo() {
        let start = ConversationLanguages().applying([.recorded("en-US")])
        let switched = start.applying([.replaced("en-US", with: "fr-FR")])
        XCTAssertEqual(switched.all, ["fr-FR"])
        XCTAssertEqual(switched.current, "fr-FR")
        let undone = switched.applying([.replaced("fr-FR", with: "en-US")])
        XCTAssertEqual(undone, ConversationLanguages(current: "en-US", all: ["en-US"]))
        let both = ConversationLanguages(current: "fr-FR", all: ["en-US", "fr-FR"])
            .applying([.replaced("fr-FR", with: "en-US")])
        XCTAssertEqual(both.all, ["en-US"], "the replaced language goes when the other is already there")
        XCTAssertEqual(ConversationLanguages().applying([.replaced("de", with: "fr")]).all, ["fr"])
        XCTAssertEqual(ConversationLanguages().applying([.replaced("fr", with: "fr")]).all, ["fr"])
        XCTAssertEqual(ConversationLanguages().applying([.replaced("", with: "fr")]).all, [])
    }

    func testChangesReappliedToTheirOwnResultGiveTheSameLanguages() {
        let changes: [ConversationLanguages.Change] = [.recorded("en-US"), .recorded("fr-FR"),
                                                       .replaced("fr-FR", with: "en-US"), .recorded("de-DE")]
        let once = ConversationLanguages().applying(changes)
        XCTAssertEqual(once.applying(changes), once)
        XCTAssertEqual(once.all, ["en-US", "de-DE"])
    }

    func testRecordsWithoutLanguagesStillDecodeAndKeepThemOnceSaved() throws {
        let old = #"{"id":"a","title":"T","date":0,"transcript":"","summary":""}"#
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(old.utf8))
        XCTAssertNil(decoded.language)
        XCTAssertNil(decoded.languages)
        XCTAssertTrue(decoded.conversationLanguages.isEmpty)
        let watched = decoded.recording(language: "it_IT")
        let roundTrip = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(watched))
        XCTAssertEqual(roundTrip.language, "it-IT")
        XCTAssertEqual(roundTrip.languages, ["it-IT"])
        XCTAssertNil(watched.with(languages: ConversationLanguages()).languages)
    }
}
