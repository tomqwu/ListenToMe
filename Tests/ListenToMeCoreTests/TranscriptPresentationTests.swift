import XCTest
@testable import ListenToMeCore

final class TranscriptPresentationTests: XCTestCase {
    private func line(_ text: String, _ start: Double, run: UUID?, end: Double? = nil,
                      source: SpeakerSource = .others) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true, start: start,
                          end: end ?? start + 1, speakerID: "voice", recordingID: run)
    }

    func testDelayedChannelsDisplayChronologicallyWithoutChangingCanonicalIdentity() {
        let run = UUID(), store = ConversationStore()
        let late = line("Later microphone", 20, run: run, source: .you)
        let early = line("Earlier system audio", 17, run: run)
        let veryEarly = line("Much delayed system audio", 1, run: run)
        [late, early, veryEarly].forEach(store.apply)
        let revision = store.revision
        XCTAssertEqual(store.presentedUtterances, [veryEarly, early, late])
        XCTAssertEqual(store.utterances, [late, early, veryEarly])
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.presentedUtterances, [veryEarly, early, late], "Cached reads preserve the same full lines")
        XCTAssertEqual(store.youCount, 1)
        XCTAssertEqual(store.othersCount, 2)
        XCTAssertTrue(store.edit(id: early.id, text: "Edited system audio"))
        XCTAssertEqual(store.utterances[1].recordingID, run)
        XCTAssertEqual(store.presentedUtterances.map(\.id), [veryEarly.id, early.id, late.id])
        store.renameSpeaker(id: "voice", name: "Dana")
        XCTAssertEqual(store.presentedUtterances.map(\.speakerName), ["Dana", "Dana", "Dana"])
        XCTAssertTrue(store.delete(id: early.id))
        XCTAssertEqual(store.presentedUtterances.map(\.id), [veryEarly.id, late.id])
        store.restore([late, early])
        XCTAssertEqual(store.presentedUtterances, [early, late])
        store.reset()
        XCTAssertTrue(store.presentedUtterances.isEmpty)
    }

    func testStableTiesAndExplicitRunsNeverCrossUntimedOrUnknownBoundaries() {
        let a = UUID(), b = UUID()
        let first = line("Tie one", 20, run: a), tie = line("Tie two", 20, run: a)
        let early = line("Early", 17, run: a), untimed = line("Untimed", 0, run: a, end: 0)
        let after = line("After untimed", 1, run: a)
        let second = line("New recording", 0, run: b)
        let legacyLater = line("Legacy later", 8, run: nil), legacyEarlier = line("Legacy earlier", 1, run: nil)
        let input = [first, tie, early, untimed, after, second, legacyLater, legacyEarlier]
        XCTAssertEqual(TranscriptPresentation.ordered(input), [early, first, tie, untimed, after, second, legacyLater, legacyEarlier])
        for invalid in [Double.nan, .infinity, -1] {
            let barrier = line("Invalid", invalid, run: a)
            XCTAssertEqual(TranscriptPresentation.ordered([first, barrier, early]).map(\.id), [first.id, barrier.id, early.id])
        }
    }

    func testRunSurvivesCodingShiftingAndLegacyDecoding() throws {
        let original = line("Saved", 17, run: UUID())
        let saved = try JSONDecoder().decode(TranscriptSegment.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(saved, original)
        XCTAssertEqual(saved.shifted(by: 8).recordingID, original.recordingID)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "recordingID")
        XCTAssertNil(try JSONDecoder().decode(TranscriptSegment.self, from: JSONSerialization.data(withJSONObject: legacy)).recordingID)
    }

    func testDurationUsesExplicitRunsAndLegacyFallbackWithoutSplittingLateChannels() throws {
        let run = UUID(), next = UUID()
        let late = line("Later", 40, run: run), early = line("Earlier", 1, run: run)
        let second = line("Second recording", 42, run: next, end: 44)
        let legacy = [line("Old later", 30, run: nil), line("Old restart", 1, run: nil)]
        XCTAssertEqual(TranscriptTimestamp.recordings([late, early]).count, 1)
        XCTAssertEqual(TranscriptTimestamp.duration(of: [late, early]), 40)
        XCTAssertEqual(TranscriptTimestamp.recordings([late, early, second] + legacy).count, 4)
        XCTAssertEqual(TranscriptTimestamp.duration(of: [late, early, second] + legacy), 44)
        let record = SessionRecord(id: "duration", title: "T", date: Date(), transcript: "", summary: "",
                                   segments: [late, early])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SessionExporter.json(for: record).utf8)) as? [String: Any])
        XCTAssertEqual(json["duration"] as? Double, 40)
    }

    func testReadableExportsOrderKnownRunsWhileJSONKeepsCanonicalOrder() throws {
        let run = UUID(), later = line("Later", 40, run: run), earlier = line("Earlier", 1, run: run)
        let record = SessionRecord(id: "r", title: "T", date: Date(timeIntervalSince1970: 0),
                                   transcript: "", summary: "", segments: [later, earlier])
        for format in [SessionExportFormat.markdown, .plainText, .srt, .webVTT] {
            let output = SessionExporter.export(record, as: format)
            XCTAssertLessThan(try XCTUnwrap(output.range(of: "Earlier")).lowerBound,
                              try XCTUnwrap(output.range(of: "Later")).lowerBound, "\(format)")
        }
        XCTAssertEqual(record.segments, [later, earlier])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SessionExporter.json(for: record).utf8)) as? [String: Any])
        let rows = try XCTUnwrap(json["segments"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["text"] as? String }, ["Later", "Earlier"])
        let nextRun = line("Next run", 0, run: UUID())
        XCTAssertEqual(SessionExporter.cues(for: [later, earlier, nextRun]).map(\.text), ["Earlier", "Later", "Next run"])
        let vault = MarkdownVault.note(for: record).markdown
        XCTAssertLessThan(try XCTUnwrap(vault.range(of: "Earlier")).lowerBound,
                          try XCTUnwrap(vault.range(of: "Later")).lowerBound)
    }
}
