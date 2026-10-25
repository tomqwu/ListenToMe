import XCTest
@testable import ListenToMeCore

final class LanguageAudioActivityTests: XCTestCase {
    func testEnergyWindowsKeepSilenceAndInvalidSamplesOutOfActivity() {
        let rate = LanguageDetectionPolicy.sampleRate
        let samples = [Float](repeating: 0, count: rate) + [Float](repeating: 0.1, count: rate * 2)
            + [Float](repeating: 0.001, count: rate) + [Float](repeating: .nan, count: 320)
            + [Float](repeating: .infinity, count: 320) + [Float](repeating: 0.1, count: 319)
        XCTAssertEqual(LanguageAudioActivity.ranges(in: samples, startSample: 10 * rate), [11..<13])
        XCTAssertTrue(LanguageAudioActivity.ranges(in: [], startSample: 0).isEmpty)
        XCTAssertTrue(LanguageAudioActivity.ranges(in: samples, startSample: -1).isEmpty)
    }

    func testMinuteOfActiveAudioRechecksWithoutAnyRecognizerEvents() {
        var tracker = LanguageTracker(locale: "en-US", resumed: true)
        let activity = LanguageAudioActivity.ranges(in: [Float](repeating: 0.1, count: 60 * 16_000), startSample: 0)
        tracker.noteAudioActivity(activity)
        XCTAssertEqual(tracker.gate(now: 60, pinned: false, conditions: .init()), .check(30..<60))
        XCTAssertEqual(tracker.gate(now: 60, pinned: true, conditions: .init()), .wait)
        XCTAssertEqual(tracker.gate(now: 60, pinned: false, conditions: .init(lowPower: true)), .skip(.lowPower))
    }

    func testSilentAudioDoesNotInventSpeechOrTriggerARecheck() {
        var tracker = LanguageTracker(locale: "en-US", resumed: true)
        tracker.noteAudioActivity(LanguageAudioActivity.ranges(
            in: [Float](repeating: 0, count: 60 * 16_000), startSample: 0))
        XCTAssertNil(tracker.speechStart)
        XCTAssertEqual(tracker.gate(now: 60, pinned: false, conditions: .init()), .skip(.silence))
    }

    func testSparseEnergyCannotTriggerInitialDetectionAndLateSpeechUsesHeldAudio() {
        var tracker = LanguageTracker(locale: "en-US")
        tracker.noteAudioActivity([0..<0.02, 20..<20.02])
        XCTAssertEqual(tracker.gate(now: 30, pinned: false, conditions: .init()), .wait)
        tracker.noteAudioActivity([180..<192])
        XCTAssertEqual(tracker.gate(now: 192, pinned: false, conditions: .init()), .check(179.5..<192))
    }

    func testEarlyEnergyCannotMoveLaterRecognizerSpeechBackIntoDiscardedAudio() {
        var tracker = LanguageTracker(locale: "en-US")
        tracker.noteAudioActivity([0..<0.02])
        XCTAssertNil(tracker.reportedSpeechStart)
        tracker.noteSpeech(start: 180, end: 182)
        XCTAssertEqual(tracker.reportedSpeechStart, 180)
        XCTAssertEqual(tracker.gate(now: 182, pinned: false, conditions: .init()), .wait)
        tracker.noteSpeech(start: 182, end: 190)
        XCTAssertEqual(tracker.gate(now: 190, pinned: false, conditions: .init()), .check(179.5..<190))
    }

    func testAudioAndRecognizerRangesAreAUnionAndOldActivityIsDiscarded() {
        var tracker = LanguageTracker(locale: "en-US", resumed: true)
        tracker.noteSpeech(start: 40, end: 50)
        tracker.noteAudioActivity([45..<60, 45..<60, -1..<0, 60..<60, 70..<Double.infinity])
        XCTAssertEqual(tracker.speech(in: 30..<60), 20)
        tracker.noteAudioActivity([220..<230])
        XCTAssertEqual(tracker.speech(in: 30..<60), 0)
        XCTAssertEqual(tracker.speech(in: 220..<230), 10)
    }
}
