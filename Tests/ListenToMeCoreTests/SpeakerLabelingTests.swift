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
        let labels = SpeakerLabeling.label(transcript: [l0, l1, l2, l3], diarized: diarized, offset: 0)
        XCTAssertEqual(labels[l0.id], "Speaker 1")
        XCTAssertEqual(labels[l1.id], "Speaker 2")
        XCTAssertEqual(labels[l2.id], "Speaker 1")
        XCTAssertEqual(labels[l3.id], "Speaker 2")
    }

    func testYouLinesExcluded() {
        let youLine = you(0, 2), othersLine = others(2, 4)
        let diarized = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 2),
            DiarizedSegment(speakerId: "A", start: 2, duration: 2)
        ]
        let labels = SpeakerLabeling.label(transcript: [youLine, othersLine], diarized: diarized, offset: 0)
        XCTAssertNil(labels[youLine.id])
        XCTAssertEqual(labels[othersLine.id], "Speaker 1")
    }

    func testOffsetShiftsAlignment() {
        // Line at capture-time [10, 12]. Diarized segments are buffer-relative; the buffer began at
        // capture-time t0 = 10, so segment B [0,2] truly covers [10,12]. Without the offset, segment
        // A [10,12] would wrongly win.
        let line = others(10, 12)
        let diarized = [
            DiarizedSegment(speakerId: "B", start: 0, duration: 2),    // shifted -> [10,12]
            DiarizedSegment(speakerId: "A", start: 10, duration: 2)    // shifted -> [20,22]
        ]
        let withOffset = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 10)
        XCTAssertEqual(withOffset[line.id], "Speaker 1")   // B is first appearance

        let withoutOffset = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        // Without offset, A [10,12] overlaps the line and B [0,2] does not -> A wins (Speaker 1).
        XCTAssertEqual(withoutOffset[line.id], "Speaker 1")
        // The two runs must disagree on which underlying speaker was matched: prove it via a 2-line
        // case where offset changes the assignment outcome.
        let lineA = others(0, 2), lineB = others(10, 12)
        let segs = [
            DiarizedSegment(speakerId: "X", start: 0, duration: 2),
            DiarizedSegment(speakerId: "Y", start: 10, duration: 2)
        ]
        // offset 0: lineA->X (Speaker 1), lineB->Y (Speaker 2).
        let none = SpeakerLabeling.label(transcript: [lineA, lineB], diarized: segs, offset: 0)
        XCTAssertEqual(none[lineA.id], "Speaker 1")
        XCTAssertEqual(none[lineB.id], "Speaker 2")
        // offset 10 shifts both segments +10: X->[10,12] now matches lineB, Y->[20,22] matches nothing.
        let shifted = SpeakerLabeling.label(transcript: [lineA, lineB], diarized: segs, offset: 10)
        XCTAssertNil(shifted[lineA.id])               // no segment overlaps [0,2] after the shift
        XCTAssertEqual(shifted[lineB.id], "Speaker 1") // X now wins lineB
    }

    func testZeroLengthLinesExcluded() {
        // Default SpeechAnalyzer emits start == end == 0; such lines must not be labeled.
        let degenerate = others(0, 0)
        let real = others(0, 2)
        let diarized = [DiarizedSegment(speakerId: "A", start: 0, duration: 2)]
        let labels = SpeakerLabeling.label(transcript: [degenerate, real], diarized: diarized, offset: 0)
        XCTAssertNil(labels[degenerate.id])
        XCTAssertEqual(labels[real.id], "Speaker 1")
    }

    func testEmptyDiarizedYieldsEmptyMap() {
        let line = others(0, 2)
        XCTAssertTrue(SpeakerLabeling.label(transcript: [line], diarized: [], offset: 0).isEmpty)
    }

    func testNonOverlappingLineIsUnlabeled() {
        let line = others(100, 102)
        let diarized = [DiarizedSegment(speakerId: "A", start: 0, duration: 2)]
        XCTAssertTrue(SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0).isEmpty)
    }

    func testTieBreaksToEarliestSegment() {
        // Line [0,4] overlaps two segments by an equal 2 s; the earlier (input-order) segment wins.
        let line = others(0, 4)
        let diarized = [
            DiarizedSegment(speakerId: "first", start: 0, duration: 2),   // overlap 2
            DiarizedSegment(speakerId: "second", start: 2, duration: 2)   // overlap 2
        ]
        let labels = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(labels[line.id], "Speaker 1")   // matched "first"
        XCTAssertEqual(labels.count, 1)
    }

    func testZeroDurationDiarizedSegmentsIgnored() {
        let line = others(0, 2)
        let diarized = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 0),   // ignored
            DiarizedSegment(speakerId: "B", start: 0, duration: 2)
        ]
        let labels = SpeakerLabeling.label(transcript: [line], diarized: diarized, offset: 0)
        XCTAssertEqual(labels[line.id], "Speaker 1")   // B, since A had zero duration
    }
}
