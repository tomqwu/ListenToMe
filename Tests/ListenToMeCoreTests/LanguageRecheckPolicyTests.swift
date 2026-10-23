import XCTest
@testable import ListenToMeCore

/// Issue #199: re-check the spoken language during a recording, with hysteresis, a minimum dwell, a
/// switch limit and pauses that save battery, and find where the language changed.
final class LanguageRecheckPolicyTests: XCTestCase {
    private typealias Policy = LanguageRecheckPolicy
    private let supported = ["en-US", "en-GB", "zh-CN", "zh-TW", "fr-FR", "es-ES"]
    private let normal = LanguageRecheckPolicy.Conditions()

    /// Continuous speech from `start` to `end`, as the transcriber reports it: a line every five seconds.
    private func speak(_ tracker: inout LanguageTracker, from start: TimeInterval, to end: TimeInterval) {
        var time = start
        while time < end {
            tracker.noteSpeech(start: time, end: min(end, time + 4.5))
            time += 5
        }
    }

    @discardableResult
    private func check(_ tracker: inout LanguageTracker, _ language: String, _ probability: Double = 0.95,
                       at now: TimeInterval, pinned: Bool = false) -> LanguageTracker.Outcome {
        tracker.record(detected: language, probability: probability, window: max(0, now - 30)..<now,
                       supported: supported, region: "US", pinned: pinned)
    }

    /// A recording in English whose first check kept English at 10 s.
    private func englishRecording() -> LanguageTracker {
        var tracker = LanguageTracker(locale: "en-US")
        speak(&tracker, from: 1, to: 10)
        XCTAssertEqual(check(&tracker, "en", at: 10), .keep(.sameLanguage))
        return tracker
    }

    // MARK: First check (issue #197)

    func testTheFirstCheckWaitsForEnoughSpeechAndStartsJustBeforeIt() {
        var tracker = LanguageTracker(locale: "en-US")
        XCTAssertEqual(tracker.phase, .first)
        XCTAssertEqual(tracker.due(now: 0), Policy.interval, "Re-checks are timed from the recording's start")
        XCTAssertEqual(tracker.gate(now: 60, pinned: false, conditions: normal), .wait, "No speech, no check")
        tracker.noteSpeech(start: 5, end: 12)
        XCTAssertEqual(tracker.gate(now: 12, pinned: false, conditions: normal), .wait, "Seven seconds is not enough")
        tracker.noteSpeech(start: 12, end: 13)
        XCTAssertEqual(tracker.gate(now: 13, pinned: false, conditions: normal), .check(4.5..<13))
        XCTAssertEqual(tracker.gate(now: 60, pinned: false, conditions: normal), .check(4.5..<34.5),
                       "Whisper reads at most 30 seconds")
        XCTAssertEqual(tracker.gate(now: 13, pinned: true, conditions: normal), .wait, "A fixed language never checks")
    }

    func testTheFirstCheckIgnoresEnergyConditionsAndASpeechTimeBeyondTheAudio() {
        var tracker = LanguageTracker(locale: "en-US")
        tracker.noteSpeech(start: 0.2, end: 9)
        let hot = Policy.Conditions(lowPower: true, background: true, thermal: true)
        XCTAssertEqual(tracker.gate(now: 9, pinned: false, conditions: hot), .check(0..<9),
                       "The single first check runs even in Low Power Mode")
        var late = LanguageTracker(locale: "en-US")
        late.noteSpeech(start: 50, end: 60)
        XCTAssertEqual(late.gate(now: 10, pinned: false, conditions: normal), .check(49.5..<49.5),
                       "A stale speech time never reaches past the audio")
    }

    func testTheFirstCheckSwitchesAtOnceFromTheRecordingsStart() {
        var tracker = LanguageTracker(locale: "en-US")
        speak(&tracker, from: 1, to: 10)
        XCTAssertEqual(check(&tracker, "zh", 0.97, at: 10), .switchTo("zh-CN", since: 0))
        XCTAssertEqual(tracker.phase, .rechecking)
        tracker.didSwitch(to: "zh-CN", at: 11)
        XCTAssertEqual(tracker.locale, "zh-CN")
        XCTAssertEqual(tracker.switches, 1)
        XCTAssertEqual(tracker.lastSwitch, 11)
    }

    func testAFirstCheckThatKeepsTheLanguageStartsTheReChecks() {
        var tracker = LanguageTracker(locale: "en-US")
        speak(&tracker, from: 1, to: 10)
        XCTAssertEqual(check(&tracker, "zh", 0.5, at: 10), .keep(.lowConfidence))
        XCTAssertEqual(tracker.phase, .rechecking)
        XCTAssertEqual(tracker.lastCheck, 10)
        XCTAssertNil(tracker.candidate, "The first check never waits for a confirmation")
    }

    // MARK: Schedule

    func testReChecksRunEveryIntervalOnTheTrailingWindow() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 75)
        XCTAssertEqual(tracker.gate(now: 69, pinned: false, conditions: normal), .wait)
        XCTAssertEqual(tracker.gate(now: 70, pinned: false, conditions: normal), .check(40..<70))
        XCTAssertEqual(check(&tracker, "en", at: 70), .keep(.sameLanguage))
        XCTAssertEqual(tracker.heardThrough, 70)
        XCTAssertEqual(tracker.gate(now: 129, pinned: false, conditions: normal), .wait)
        speak(&tracker, from: 75, to: 130)
        XCTAssertEqual(tracker.gate(now: 130, pinned: false, conditions: normal), .check(100..<130))
    }

    func testReChecksSkipSilenceAndRunOnceSpeechReturns() {
        var tracker = englishRecording()
        tracker.noteSpeech(start: 60, end: 66)
        XCTAssertEqual(tracker.gate(now: 75, pinned: false, conditions: normal), .skip(.silence),
                       "Six seconds of speech in the window is too little to check")
        tracker.noteSpeech(start: 70, end: 75)
        XCTAssertEqual(tracker.gate(now: 76, pinned: false, conditions: normal), .check(46..<76))
    }

    func testReChecksPauseInLowPowerModeInTheBackgroundAndWhenHot() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 75)
        func gate(_ conditions: Policy.Conditions) -> LanguageTracker.Gate {
            tracker.gate(now: 75, pinned: false, conditions: conditions)
        }
        XCTAssertEqual(gate(.init(lowPower: true, background: true, thermal: true)), .skip(.lowPower))
        XCTAssertEqual(gate(.init(background: true, thermal: true)), .skip(.background))
        XCTAssertEqual(gate(.init(thermal: true)), .skip(.thermal))
        XCTAssertEqual(gate(normal), .check(45..<75))
        XCTAssertEqual(tracker.gate(now: 75, pinned: true, conditions: normal), .wait, "Undo pins; checks stop")
    }

    func testAResumedRecordingStartsWithReChecks() {
        var tracker = LanguageTracker(locale: "zh-CN", resumed: true)
        XCTAssertEqual(tracker.phase, .rechecking)
        speak(&tracker, from: 0, to: 61)
        XCTAssertEqual(tracker.gate(now: 30, pinned: false, conditions: normal), .wait,
                       "A resumed recording is not checked again at once")
        XCTAssertEqual(tracker.gate(now: 60, pinned: false, conditions: normal), .check(30..<60))
    }

    // MARK: Hysteresis

    func testADifferentLanguageMustBeHeardTwiceInARow() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 100)
        XCTAssertEqual(check(&tracker, "fr", at: 70), .confirming("fr-FR"))
        XCTAssertEqual(tracker.candidate?.locale, "fr-FR")
        XCTAssertEqual(tracker.gate(now: 89, pinned: false, conditions: normal), .wait)
        XCTAssertEqual(tracker.gate(now: 90, pinned: false, conditions: normal), .check(60..<90),
                       "The confirmation comes sooner than the next regular check")
        guard case .locate("fr-FR", let span) = check(&tracker, "fr", at: 90) else {
            return XCTFail("A second agreeing check confirms the switch")
        }
        XCTAssertEqual(span, 0..<90, "The span reaches back half a window before English was last heard (10 s)")
        XCTAssertNil(tracker.candidate)
    }

    func testAShortPhraseInAnotherLanguageDoesNotFlipTheTranscriber() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 100)
        XCTAssertEqual(check(&tracker, "fr", at: 70), .confirming("fr-FR"))
        XCTAssertEqual(check(&tracker, "en", at: 90), .keep(.sameLanguage), "Back in English: the candidate is dropped")
        XCTAssertNil(tracker.candidate)
        XCTAssertEqual(tracker.due(now: 90), 150, "The next regular check is an interval later")
    }

    func testAnUnsureConfirmationOrAThirdLanguageDoesNotConfirm() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 130)
        XCTAssertEqual(check(&tracker, "fr", at: 70), .confirming("fr-FR"))
        XCTAssertEqual(check(&tracker, "fr", 0.6, at: 90), .keep(.lowConfidence))
        XCTAssertNil(tracker.candidate, "Hysteresis needs two confident checks in a row")
        XCTAssertEqual(check(&tracker, "fr", at: 100), .confirming("fr-FR"))
        XCTAssertEqual(check(&tracker, "es", at: 120), .confirming("es-ES"), "A different language starts over")
        XCTAssertEqual(tracker.candidate?.locale, "es-ES")
    }

    func testAStaleCandidateIsForgotten() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 200)
        XCTAssertEqual(check(&tracker, "fr", at: 70), .confirming("fr-FR"))
        XCTAssertEqual(tracker.due(now: 100), 90)
        XCTAssertEqual(tracker.due(now: 131), 130, "Unconfirmed for an interval, it falls back to the regular check")
        XCTAssertEqual(check(&tracker, "fr", at: 140), .confirming("fr-FR"),
                       "A check after the candidate expired starts a new candidate rather than switching")
    }

    // MARK: Dwell and limits

    func testASwitchStaysForTheMinimumDwell() {
        var tracker = englishRecording()
        tracker.didSwitch(to: "fr-FR", at: 100)
        speak(&tracker, from: 100, to: 300)
        XCTAssertEqual(tracker.gate(now: 159, pinned: false, conditions: normal), .wait)
        XCTAssertEqual(check(&tracker, "en", at: 160), .confirming("en-US"))
        XCTAssertEqual(tracker.due(now: 160), 190, "The confirmation waits for the dwell, not just 20 seconds")
        XCTAssertEqual(tracker.gate(now: 185, pinned: false, conditions: normal), .wait)
        XCTAssertEqual(check(&tracker, "en", at: 185), .confirming("en-US"),
                       "Even an agreeing check inside the dwell does not switch")
        guard case .locate("en-US", let span) = check(&tracker, "en", at: 205) else {
            return XCTFail("After the dwell the switch back is confirmed")
        }
        XCTAssertEqual(span.lowerBound, 100, "Never before the last switch")
    }

    func testARecordingStopsReCheckingAtItsSwitchLimit() {
        var tracker = englishRecording()
        let languages = ["fr-FR", "en-US", "fr-FR", "en-US"]
        for (index, locale) in languages.enumerated() {
            tracker.didSwitch(to: locale, at: TimeInterval(100 + index * 100))
        }
        XCTAssertEqual(tracker.switches, Policy.maximumSwitches)
        speak(&tracker, from: 400, to: 600)
        XCTAssertEqual(tracker.gate(now: 600, pinned: false, conditions: normal), .wait,
                       "No more checks, so no more battery spent on them")
        XCTAssertEqual(check(&tracker, "fr", at: 600), .keep(.switchLimit))
    }

    func testAnUnsupportedOrFailedLocaleNeverBecomesACandidate() {
        var tracker = englishRecording()
        speak(&tracker, from: 10, to: 200)
        XCTAssertEqual(check(&tracker, "sw", at: 70), .keep(.unsupported))
        XCTAssertNil(tracker.candidate)
        tracker.switchFailed(to: "fr-FR")
        XCTAssertEqual(check(&tracker, "fr", at: 130), .keep(.unsupported),
                       "A locale whose model could not be prepared is not tried again in this recording")
        XCTAssertEqual(tracker.unavailable, ["fr-FR"])
    }

    func testUndoGoesBackAndDropsTheCandidate() {
        var tracker = englishRecording()
        tracker.didSwitch(to: "fr-FR", at: 100)
        speak(&tracker, from: 100, to: 170)
        XCTAssertEqual(check(&tracker, "en", at: 160), .confirming("en-US"))
        tracker.undone(to: "en-US")
        XCTAssertEqual(tracker.locale, "en-US")
        XCTAssertNil(tracker.candidate)
        XCTAssertEqual(check(&tracker, "en", at: 170, pinned: true), .keep(.pinned))
    }

    func testAMissedCheckCountsAsACheck() {
        var tracker = LanguageTracker(locale: "en-US")
        speak(&tracker, from: 1, to: 80)
        tracker.missed(at: 10)
        XCTAssertEqual(tracker.phase, .rechecking, "A failing first check is not retried on every speech event")
        XCTAssertEqual(tracker.gate(now: 69, pinned: false, conditions: normal), .wait)
        XCTAssertEqual(check(&tracker, "fr", at: 70), .confirming("fr-FR"))
        tracker.missed(at: 90)
        XCTAssertNil(tracker.candidate, "An unconfirmed candidate is dropped")
        XCTAssertEqual(tracker.due(now: 90), 150)
    }

    // MARK: Speech bookkeeping

    func testSpeechIsMergedInAnyOrderAndForgottenWithItsAudio() {
        var tracker = LanguageTracker(locale: "en-US")
        tracker.noteSpeech(start: 10, end: 12)
        tracker.noteSpeech(start: 2, end: 4)
        tracker.noteSpeech(start: 3, end: 11)
        tracker.noteSpeech(start: 20, end: 20)
        tracker.noteSpeech(start: .nan, end: 30)
        XCTAssertEqual(tracker.speech(in: 0..<100), 10, accuracy: 0.001, "2–12 once, however it was reported")
        XCTAssertEqual(tracker.speech(in: 5..<8), 3, accuracy: 0.001)
        XCTAssertEqual(tracker.speechStart, 2)
        XCTAssertEqual(tracker.speechEnd, 20)
        tracker.noteSpeech(start: 400, end: 401)
        XCTAssertEqual(tracker.speech(in: 0..<100), 0, "Speech older than the held audio is forgotten")
    }

    // MARK: A whole recording

    /// The issue's acceptance case: English, then Mandarin from 2:20. The switch is confirmed, the change
    /// is found within one chunk, and only the Mandarin span is transcribed again.
    func testEnglishThenMandarinAfterTwoMinutes() {
        var tracker = englishRecording()
        var checks: [TimeInterval] = []
        var outcome: LanguageTracker.Outcome?
        var now: TimeInterval = 10
        while now < 300, outcome == nil {
            now += 1
            tracker.noteSpeech(start: now - 1, end: now - 0.2)
            guard case .check(let window) = tracker.gate(now: now, pinned: false, conditions: normal) else { continue }
            checks.append(now)
            let heard = window.lowerBound + 15 >= 140 ? "zh" : "en"
            let result = tracker.record(detected: heard, probability: 0.95, window: window, supported: supported,
                                        region: "US", pinned: false)
            if case .locate = result { outcome = result }
        }
        XCTAssertEqual(checks, [70, 130, 190, 210], "Every minute, then a confirmation 20 seconds later")
        guard case .locate("zh-CN", let span) = outcome else { return XCTFail("Mandarin is confirmed") }
        XCTAssertEqual(span, 115..<210, "From half a window before English was last heard")
        let chunks = Policy.scanChunks(span) { tracker.speech(in: $0) }
        XCTAssertEqual(chunks.count, 10)
        let scanned = chunks.map { ($0, $0.upperBound <= 140 ? Policy.Verdict.current : .target) }
        XCTAssertEqual(Policy.changePoint(in: span, scanned: scanned), 135,
                       "The replay starts at the chunk holding the change, not at the span's or recording's start")
    }
}
