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
        XCTAssertTrue(SessionExporter.srt(for: record([line("a --> b", 1, 2)])).contains("a --› b"))
    }

    // MARK: Review of #233

    /// Finding 5 and 9: no cue text can hold `-->` however many dashes precede it, and SubRip text
    /// never carries `<…>` tags or `&…;` entities a player would interpret.
    func testSRTTextIsSafeForPlayers() {
        let srt = SessionExporter.srt(for: record([line("a ---> b <i>x</i> &amp; c", 1, 2)]))
        let text = srt.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        XCTAssertFalse(text.contains("-->"), srt)
        XCTAssertFalse(text.contains("<") || text.contains(">") || text.contains("&"), srt)
        XCTAssertTrue(text.contains("a ---› b ‹i›x‹/i› ＆amp; c"), srt)
        XCTAssertEqual(SessionExporter.srtSafe(SessionExporter.srtSafe("a<b")), "a‹b")
    }

    /// Finding 6: with several speakers the `Speaker: ` prefix counts toward the cue limit, so every SRT
    /// cue fits in two lines of 42.
    func testNamedSRTCuesStayWithinTwoLines() {
        let long = String(repeating: "word ", count: 16) + "end"   // 83 characters
        let srt = SessionExporter.srt(for: record([line(long, 1, 6, speaker: "Alexandra"),
                                                   line("Yes.", 7, 8, speaker: "Bob")]))
        for cue in srt.components(separatedBy: "\n\n") {
            let textLines = cue.split(separator: "\n").dropFirst(2)
            XCTAssertLessThanOrEqual(textLines.count, 2, srt)
            XCTAssertTrue(textLines.allSatisfy { $0.count <= SessionExporter.maximumLineCharacters }, srt)
        }
        XCTAssertTrue(srt.contains("Alexandra: "), srt)
    }

    /// Finding 8: a long line timed with no length is spread over an estimated reading time, never past
    /// the next line, instead of stacking every piece at one instant.
    func testZeroLengthLongLineGetsSequentialCues() {
        let long = String(repeating: "word ", count: 40) + "end"   // 203 characters, about 13.5 s to read
        let cues = SessionExporter.cues(for: [line(long, 10, 10), line("Next.", 30, 31)])
        let pieces = cues.dropLast()
        XCTAssertGreaterThan(pieces.count, 1)
        XCTAssertTrue(zip(pieces, pieces.dropFirst()).allSatisfy { $0.end <= $1.start && $0.start < $1.start },
                      "\(pieces)")
        XCTAssertTrue(pieces.allSatisfy { $0.end > $0.start })
        XCTAssertLessThanOrEqual(pieces.last?.end ?? 0, 30)
        let clamped = SessionExporter.cues(for: [line(long, 10, 10), line("Next.", 12, 13)])
        XCTAssertEqual(clamped.dropLast().last?.end, 12, "never past the next line's start")
    }

    /// Finding 1 (exporter side): conversations saved before each Mac capture continued the timeline
    /// restart at zero for every Listen. Lines are never merged across that regression, and the
    /// duration adds up the recordings instead of reporting the longest.
    func testRecordingsThatRestartAtZeroAreKeptApart() {
        let first = [line("One.", 1, 2, speaker: "A"), line("Two.", 50, 60, speaker: "A")]
        let second = [line("Three.", 1.5, 2.5, speaker: "A"), line("Four.", 20, 30, speaker: "A")]
        let spans = TranscriptTimestamp.recordings(first + second)
        XCTAssertEqual(spans.map { $0.map(\.text) }, [["One.", "Two."], ["Three.", "Four."]])
        XCTAssertEqual(TranscriptTimestamp.duration(of: first + second), 59 + 28.5)
        let cues = SessionExporter.cues(for: first + second)
        XCTAssertEqual(cues.map(\.text), ["One.", "Two.", "Three.", "Four."], "nothing merged or interleaved")
        // Two channels finalizing a few seconds out of order stay one recording.
        let outOfOrder = [line("Late", 8, 9, speaker: "A"), line("Early", 3, 4, speaker: "B")]
        XCTAssertEqual(TranscriptTimestamp.recordings(outOfOrder).count, 1)
    }

    /// Finding 7: the whole file name stays within 200 UTF-8 bytes, cut on whole characters.
    func testFileNameIsCappedInBytesOnCharacterBoundaries() {
        for title in [String(repeating: "👨‍👩‍👧‍👦", count: 60), String(repeating: "会议记录", count: 15),
                      String(repeating: "ä", count: 60)] {
            let name = SessionExporter.fileName(title: title, date: date, fileExtension: "json", suffix: "recap",
                                                timeZone: utc)
            XCTAssertLessThanOrEqual(name.utf8.count, SessionExporter.maximumNameBytes, name)
            XCTAssertTrue(name.hasSuffix(" 2026-10-23 1435 recap.json"), name)
            XCTAssertTrue(name.unicodeScalars.allSatisfy { $0.properties.generalCategory != .unassigned })
            let stem = name.replacingOccurrences(of: " 2026-10-23 1435 recap.json", with: "")
            XCTAssertTrue(title.hasPrefix(stem), "cut on a whole character: \(stem)")
        }
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

    private func spoken(_ text: String, _ start: TimeInterval, _ language: String?) -> TranscriptSegment {
        TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: start + 1, language: language)
    }

    func testLanguagesFollowTheLinesTheyAreIn() {
        // A first check that transcribed everything again in Chinese leaves nothing in English.
        let replayed = ConversationLanguages().resolving(recorded: ["en-US", "zh-CN"],
                                                         segments: [spoken("我们", 1, "zh-CN"), spoken("开会", 5, "zh_CN")])
        XCTAssertEqual(replayed, ConversationLanguages(current: "zh-CN", all: ["zh-CN"]))
        // Review finding 2, example A: Undo after twenty minutes of Spanish keeps Spanish listed, because
        // only the lines before the switch return to English; the current language is English again.
        let undoneA = ConversationLanguages().resolving(
            recorded: ["en-US", "es-ES", "en-US"],
            segments: [spoken("Hello", 1, "en-US"), spoken("Hola", 70, "es-ES"), spoken("Adiós", 1_200, "es-ES")])
        XCTAssertEqual(undoneA.all, ["en-US", "es-ES"])
        XCTAssertEqual(undoneA.current, "en-US")
        // Example B: an earlier German recording keeps German when an Undo of French → German follows.
        let undoneB = ConversationLanguages(current: "de-DE", all: ["de-DE", "fr-FR"]).resolving(
            recorded: ["fr-FR", "de-DE", "fr-FR"],
            segments: [spoken("Guten Tag", 1, "de-DE"), spoken("Bonjour", 100, "fr-FR")])
        XCTAssertEqual(undoneB.all, ["de-DE", "fr-FR"])
        XCTAssertEqual(undoneB.current, "fr-FR")
        // Lines saved before languages were kept per line cannot say, so nothing listed is dropped.
        let legacy = ConversationLanguages(current: "de-DE", all: ["de-DE"]).resolving(
            recorded: ["fr-FR"], segments: [spoken("Alt", 1, nil), spoken("Nouveau", 5, "fr-FR")])
        XCTAssertEqual(legacy.all, ["de-DE", "fr-FR"])
        XCTAssertEqual(ConversationLanguages().resolving(recorded: [], segments: []).all, [])
    }

    func testResolvingAgainOnItsOwnResultGivesTheSameLanguages() {
        let recorded = ["en-US", "fr-FR", "en-US", "de-DE"]
        let lines = [spoken("a", 1, "en-US"), spoken("b", 5, "fr-FR")]
        let once = ConversationLanguages().resolving(recorded: recorded, segments: lines)
        XCTAssertEqual(once.resolving(recorded: recorded, segments: lines), once)
        XCTAssertEqual(once.all, ["en-US", "fr-FR", "de-DE"], "the language being recorded now is listed")
        XCTAssertEqual(once.current, "de-DE")
    }

    func testShiftingMovesOnlyTimedLines() {
        let timed = spoken("a", 2, "en-US").shifted(by: 100)
        XCTAssertEqual([timed.start, timed.end], [102, 103])
        XCTAssertEqual(timed.language, "en-US")
        let untimed = line("b", 0, 0).shifted(by: 100)
        XCTAssertEqual([untimed.start, untimed.end], [0, 0])
        XCTAssertEqual(spoken("c", 2, nil).shifted(by: 0).start, 2)
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
