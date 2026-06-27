import XCTest
@testable import ListenToMeCore

final class SpeakerLabelingTests: XCTestCase {
    private func others(_ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(source: .others, text: "x", isFinal: true, start: start, end: end)
    }

    private func you(_ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(source: .you, text: "x", isFinal: true, start: start, end: end)
    }

    func testTwoSpeakersLabeledByAppearanceOrder() {
        let l0 = others(0, 2), l1 = others(2, 4), l2 = others(4, 6), l3 = others(6, 8)
        let diarized = [
            DiarizedSegment(speakerId: "B", start: 0, duration: 2),   // -> Speaker 1 (first appearance)
            DiarizedSegment(speakerId: "A", start: 2, duration: 2),   // -> Speaker 2
            DiarizedSegment(speakerId: "B", start: 4, duration: 2),
            DiarizedSegment(speakerId: "A", start: 6, duration: 2)
        ]
        let result = SpeakerLabeling.label(transcript: [l0, l1, l2, l3], diarized: diarized, offset: 0)
        XCTAssertEqual(result.lineLabels[l0.id], "Speaker 1")
        XCTAssertEqual(result.lineLabels[l1.id], "Speaker 2")
        XCTAssertEqual(result.lineLabels[l2.id], "Speaker 1")
        XCTAssertEqual(result.lineLabels[l3.id], "Speaker 2")
        // `order` is the canonical id->label map by first appearance.
        XCTAssertEqual(result.order, ["B": "Speaker 1", "A": "Speaker 2"])
    }

    func testYouLinesExcluded() {
        let youLine = you(0, 2), othersLine = others(2, 4)
        let diarized = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 2),
            DiarizedSegment(speakerId: "A", start: 2, duration: 2)
        ]
        let result = SpeakerLabeling.label(transcript: [youLine, othersLine], diarized: diarized, offset: 0)
        XCTAssertNil(result.lineLabels[youLine.id])
        XCTAssertEqual(result.lineLabels[othersLine.id], "Speaker 1")
    }

    func testOffsetShiftsAlignment() {
        let line = others(10, 12)
        let diarized = [
            DiarizedSegment(speakerId: "B", start: 0, duration: 2),    // shifted -> [10,12]
            DiarizedSegment(speakerId: "A", start: 10, duration: 2)    // shifted -> [20,22]
        ]
        let withOffset = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 10)
        XCTAssertEqual(withOffset.lineLabels[line.id], "Speaker 1")   // B is first appearance

        let withoutOffset = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        // Without offset, A [10,12] overlaps the line and B [0,2] does not -> A wins. Numbering is by
        // earliest audio: B (start 0) is Speaker 1, A (start 10) is Speaker 2, so the line gets 2.
        XCTAssertEqual(withoutOffset.lineLabels[line.id], "Speaker 2")
        // Prove the offset changes the underlying assignment via a 2-line case.
        let lineA = others(0, 2), lineB = others(10, 12)
        let segs = [
            DiarizedSegment(speakerId: "X", start: 0, duration: 2),
            DiarizedSegment(speakerId: "Y", start: 10, duration: 2)
        ]
        // offset 0: lineA->X (Speaker 1), lineB->Y (Speaker 2).
        let none = SpeakerLabeling.label(transcript: [lineA, lineB], diarized: segs, offset: 0)
        XCTAssertEqual(none.lineLabels[lineA.id], "Speaker 1")
        XCTAssertEqual(none.lineLabels[lineB.id], "Speaker 2")
        // offset 10 shifts both segments +10: X->[10,12] now matches lineB, Y->[20,22] matches nothing.
        let shifted = SpeakerLabeling.label(transcript: [lineA, lineB], diarized: segs, offset: 10)
        XCTAssertNil(shifted.lineLabels[lineA.id])               // no segment overlaps [0,2] after shift
        XCTAssertEqual(shifted.lineLabels[lineB.id], "Speaker 1") // X now wins lineB
    }

    func testZeroLengthLinesExcluded() {
        // Default SpeechAnalyzer emits start == end == 0; such lines must not be labeled.
        let degenerate = others(0, 0)
        let real = others(0, 2)
        let diarized = [DiarizedSegment(speakerId: "A", start: 0, duration: 2)]
        let result = SpeakerLabeling.label(transcript: [degenerate, real], diarized: diarized, offset: 0)
        XCTAssertNil(result.lineLabels[degenerate.id])
        XCTAssertEqual(result.lineLabels[real.id], "Speaker 1")
    }

    func testEmptyDiarizedYieldsEmptyResult() {
        let line = others(0, 2)
        let result = SpeakerLabeling.label(transcript: [line], diarized: [], offset: 0)
        XCTAssertTrue(result.lineLabels.isEmpty)
        XCTAssertTrue(result.order.isEmpty)
    }

    func testNonOverlappingLineIsUnlabeled() {
        let line = others(100, 102)
        let diarized = [DiarizedSegment(speakerId: "A", start: 0, duration: 2)]
        let result = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertTrue(result.lineLabels.isEmpty)
        // `order` is total: it still numbers the diarized speaker even though no line matched.
        XCTAssertEqual(result.order, ["A": "Speaker 1"])
    }

    func testOrderCoversEveryDiarizedSpeakerByEarliestAppearance() {
        // Only speaker "mid" overlaps the single transcript line; "early" (starts first) and "late"
        // never match a line. `order` must still number ALL three by earliest shifted start —
        // early (0) -> Speaker 1, mid (5) -> Speaker 2, late (9) -> Speaker 3 — so the breakdown
        // sheet can label every summary row without a colliding fallback.
        let line = others(5, 7)
        let diarized = [
            DiarizedSegment(speakerId: "mid", start: 5, duration: 2),    // matches the line
            DiarizedSegment(speakerId: "early", start: 0, duration: 2),  // no matching line
            DiarizedSegment(speakerId: "late", start: 9, duration: 2)    // no matching line
        ]
        let result = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(result.order,
                       ["early": "Speaker 1", "mid": "Speaker 2", "late": "Speaker 3"])
        // The matched line is labeled with the same canonical numbering.
        XCTAssertEqual(result.lineLabels[line.id], "Speaker 2")
        XCTAssertEqual(result.lineLabels.count, 1)
    }

    func testNumberingIsByEarliestDiarizedAppearanceNotLineOrder() {
        // The first transcript line is matched by the speaker whose audio appears LATER. Numbering is
        // audio-driven, so the earlier-appearing speaker is still Speaker 1 even though it labels a
        // later line.
        let l0 = others(0, 2), l1 = others(10, 12)
        let diarized = [
            DiarizedSegment(speakerId: "late", start: 0, duration: 2),    // earliest audio -> Speaker 1
            DiarizedSegment(speakerId: "early", start: 10, duration: 2)   // -> Speaker 2
        ]
        let result = SpeakerLabeling.label(transcript: [l0, l1], diarized: diarized, offset: 0)
        XCTAssertEqual(result.order, ["late": "Speaker 1", "early": "Speaker 2"])
        XCTAssertEqual(result.lineLabels[l0.id], "Speaker 1")   // matched "late"
        XCTAssertEqual(result.lineLabels[l1.id], "Speaker 2")   // matched "early"
    }

    func testTieBreaksToEarliestSegment() {
        // Line [0,4] overlaps two single-segment speakers by an equal 2 s; the one whose segment
        // starts earlier ("first" at 0) wins.
        let line = others(0, 4)
        let diarized = [
            DiarizedSegment(speakerId: "first", start: 0, duration: 2),   // overlap 2, starts at 0
            DiarizedSegment(speakerId: "second", start: 2, duration: 2)   // overlap 2, starts at 2
        ]
        let result = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(result.lineLabels[line.id], "Speaker 1")   // matched "first"
        XCTAssertEqual(result.lineLabels.count, 1)
        // Both speakers are numbered by earliest start: first (0) -> 1, second (2) -> 2.
        XCTAssertEqual(result.order, ["first": "Speaker 1", "second": "Speaker 2"])
    }

    func testFullTieBreaksToSmallerSpeakerId() {
        // Two speakers overlap the line equally (3 s each) AND their earliest segments start at the
        // same time (0) — the final tie-break picks the smaller speakerId for determinism.
        let line = others(0, 6)
        let diarized = [
            DiarizedSegment(speakerId: "zebra", start: 0, duration: 3),   // overlap 3, starts at 0
            DiarizedSegment(speakerId: "alpha", start: 0, duration: 3)    // overlap 3, starts at 0
        ]
        let result = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(result.lineLabels[line.id], "Speaker 1")   // "alpha" wins (smaller id)
        // Both start at 0, so numbering tie-breaks on id: alpha -> 1, zebra -> 2.
        XCTAssertEqual(result.order, ["alpha": "Speaker 1", "zebra": "Speaker 2"])
    }

    func testZeroDurationDiarizedSegmentsIgnored() {
        let line = others(0, 2)
        let diarized = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 0),   // ignored
            DiarizedSegment(speakerId: "B", start: 0, duration: 2)
        ]
        let result = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(result.lineLabels[line.id], "Speaker 1")   // B, since A had zero duration
    }

    func testSummedOverlapPerSpeakerWins() {
        // One OTHERS line spans [0, 10]. Speaker A speaks in two short pieces (split around a pause)
        // totalling 6 s of overlap; speaker B has a single 4 s piece. Comparing segments
        // independently, B's single 4 s would beat each of A's <=3 s pieces — but A's SUMMED 6 s
        // must win.
        let line = others(0, 10)
        let diarized = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 3),   // overlap 3
            DiarizedSegment(speakerId: "B", start: 3, duration: 4),   // overlap 4 (longest single)
            DiarizedSegment(speakerId: "A", start: 7, duration: 3)    // overlap 3  (A total = 6)
        ]
        let result = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(result.lineLabels[line.id], "Speaker 1")   // A, by summed overlap (6 > 4)
        XCTAssertEqual(result.order["A"], "Speaker 1")
    }
}
