import XCTest
@testable import ListenToMeCore

/// Issue #109: periodic diarization must re-analyze only a trailing window (never the whole growing
/// session) and must STOP rescheduling once the diarizer's models are unavailable.
final class SpeakerAnalysisPolicyTests: XCTestCase {

    private func seconds(_ value: Double) -> Int { Int(value * Double(SpeakerAnalysisPolicy.sampleRate)) }

    // MARK: Scheduling

    func testCompletedPassRestsAtLeastTheMinimum() {
        let started = Date(timeIntervalSince1970: 1_000)
        let finished = started.addingTimeInterval(2)
        let next = SpeakerAnalysisPolicy.nextAnalysis(passStarted: started, finished: finished,
                                                      outcome: .completed)
        XCTAssertEqual(next, finished.addingTimeInterval(SpeakerAnalysisPolicy.minimumRest))
    }

    func testSlowPassRestsAsLongAsItTook() {
        let started = Date(timeIntervalSince1970: 1_000)
        let finished = started.addingTimeInterval(45)
        let next = SpeakerAnalysisPolicy.nextAnalysis(passStarted: started, finished: finished,
                                                      outcome: .completed)
        XCTAssertEqual(next, finished.addingTimeInterval(45))
    }

    func testClockSkewNeverSchedulesInThePast() {
        let started = Date(timeIntervalSince1970: 1_000)
        let finished = started.addingTimeInterval(-30)   // clock moved backwards mid-pass
        let next = SpeakerAnalysisPolicy.nextAnalysis(passStarted: started, finished: finished,
                                                      outcome: .completed)
        XCTAssertEqual(next, finished.addingTimeInterval(SpeakerAnalysisPolicy.minimumRest))
    }

    func testUnavailableModelsStopPeriodicScheduling() {
        let started = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(SpeakerAnalysisPolicy.nextAnalysis(passStarted: started,
                                                        finished: started.addingTimeInterval(1),
                                                        outcome: .modelsUnavailable))
    }

    // MARK: Trailing window

    func testShortSessionIsAnalyzedFromTheStart() {
        XCTAssertEqual(SpeakerAnalysisPolicy.windowStartSample(totalSamples: seconds(120),
                                                               analyzedSamples: 0), 0)
    }

    func testIncrementalPassRewindsOnlyByTheOverlap() {
        let analyzed = seconds(300)
        let start = SpeakerAnalysisPolicy.windowStartSample(totalSamples: seconds(320),
                                                            analyzedSamples: analyzed)
        XCTAssertEqual(start, analyzed - seconds(SpeakerAnalysisPolicy.windowOverlap))
    }

    func testWindowNeverExceedsTheMaximum() {
        let total = seconds(7_200)   // a two-hour meeting
        let start = SpeakerAnalysisPolicy.windowStartSample(totalSamples: total, analyzedSamples: 0)
        XCTAssertEqual(start, total - seconds(SpeakerAnalysisPolicy.maximumWindow))
        XCTAssertEqual(total - start, seconds(SpeakerAnalysisPolicy.maximumWindow))
    }

    func testWindowStartIsClampedToTheBuffer() {
        XCTAssertEqual(SpeakerAnalysisPolicy.windowStartSample(totalSamples: -5, analyzedSamples: -5), 0)
        // An analyzed count beyond the buffer (after a reset) can never push the window past the end.
        XCTAssertEqual(SpeakerAnalysisPolicy.windowStartSample(totalSamples: seconds(30),
                                                               analyzedSamples: seconds(900)), 0)
    }

    func testMinimumSamplesIsThreeSeconds() {
        XCTAssertEqual(SpeakerAnalysisPolicy.minimumSamples, seconds(3))
    }

    // MARK: Status line

    func testCompletedPassHasNoStatusLine() {
        XCTAssertNil(SpeakerAnalysisPolicy.statusLine(for: .completed, detail: "ignored"))
    }

    func testUnavailableStatusMentionsTheReasonOnce() {
        let line = SpeakerAnalysisPolicy.statusLine(for: .modelsUnavailable,
                                                    detail: "The Internet connection appears to be offline.")
        XCTAssertEqual(line, "Speaker identification paused — The Internet connection appears to be offline. Press Speakers to retry.")
    }

    func testUnavailableStatusFallsBackWhenThereIsNoDetail() {
        let expected = "Speaker identification paused — speaker models could not be loaded. Press Speakers to retry."
        XCTAssertEqual(SpeakerAnalysisPolicy.statusLine(for: .modelsUnavailable, detail: nil), expected)
        XCTAssertEqual(SpeakerAnalysisPolicy.statusLine(for: .modelsUnavailable, detail: "   "), expected)
    }
}
