import XCTest
@testable import ListenToMeCore

final class SpeakerStatsTests: XCTestCase {
    func testEmptySegmentsYieldEmptySummary() {
        let summary = SpeakerStats.summarize([])
        XCTAssertEqual(summary.speakerCount, 0)
        XCTAssertEqual(summary.totalSpeech, 0)
        XCTAssertTrue(summary.speakers.isEmpty)
    }

    func testMergesMultipleSegmentsPerSpeaker() {
        let segments = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 3),
            DiarizedSegment(speakerId: "B", start: 3, duration: 1),
            DiarizedSegment(speakerId: "A", start: 4, duration: 2)
        ]
        let summary = SpeakerStats.summarize(segments)
        XCTAssertEqual(summary.speakerCount, 2)
        XCTAssertEqual(summary.totalSpeech, 6, accuracy: 1e-9)
        // Sorted by total talk-time descending: A (5s) then B (1s).
        XCTAssertEqual(summary.speakers.map(\.id), ["A", "B"])
        XCTAssertEqual(summary.speakers[0].total, 5, accuracy: 1e-9)
        XCTAssertEqual(summary.speakers[1].total, 1, accuracy: 1e-9)
    }

    func testFractionsSumToApproximatelyOne() {
        let segments = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 7),
            DiarizedSegment(speakerId: "B", start: 7, duration: 3),
            DiarizedSegment(speakerId: "C", start: 10, duration: 5)
        ]
        let summary = SpeakerStats.summarize(segments)
        let fractionSum = summary.speakers.reduce(0) { $0 + $1.fraction }
        XCTAssertEqual(fractionSum, 1.0, accuracy: 1e-9)
        XCTAssertEqual(summary.speakers[0].fraction, 7.0 / 15.0, accuracy: 1e-9)
    }

    func testZeroAndNegativeDurationSegmentsIgnored() {
        let segments = [
            DiarizedSegment(speakerId: "A", start: 0, duration: 4),
            DiarizedSegment(speakerId: "B", start: 4, duration: 0),
            DiarizedSegment(speakerId: "C", start: 4, duration: -2)
        ]
        let summary = SpeakerStats.summarize(segments)
        XCTAssertEqual(summary.speakerCount, 1)
        XCTAssertEqual(summary.totalSpeech, 4, accuracy: 1e-9)
        XCTAssertEqual(summary.speakers.map(\.id), ["A"])
    }
}
