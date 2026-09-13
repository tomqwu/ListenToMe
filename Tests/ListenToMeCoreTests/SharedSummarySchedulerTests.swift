import XCTest
@testable import ListenToMeCore

final class LiveSummarySchedulerTests: XCTestCase {
    private let start = ContinuousClock.now
    private var ready: LiveSummaryScheduler.Snapshot {
        .init(recording: true, automatic: true, pending: true, reading: false, manualQuick: false, available: true)
    }

    func testTranscriptEventsBatchAtOriginalDeadlineAndNeverEvaluateSilence() {
        var scheduler = LiveSummaryScheduler(interval: .seconds(5))
        XCTAssertEqual(scheduler.plan(.transcriptChanged, state: ready, now: start), [.cancelWake, .schedule(.seconds(5))])
        XCTAssertEqual(scheduler.plan(.transcriptChanged, state: ready, now: start + .seconds(3)),
                       [.cancelWake, .schedule(.seconds(2))], "New events must not postpone the original deadline")
        XCTAssertEqual(scheduler.plan(.timerFired, state: ready, now: start + .seconds(5)), [.cancelWake, .evaluate])
        XCTAssertEqual(scheduler.plan(.transcriptChanged, state: ready, now: start + .seconds(6)), [.cancelWake])
        var silent = ready; silent.pending = false
        XCTAssertEqual(scheduler.plan(.evaluationFinished, state: silent, now: start + .seconds(7)), [.cancelWake])
        XCTAssertEqual(scheduler.plan(.timerFired, state: silent, now: start + .seconds(30)), [.cancelWake])
    }

    func testSlowResponseCatchesUpWithoutAnotherIntervalAndFailureBacksOff() {
        var scheduler = LiveSummaryScheduler(interval: .seconds(5))
        _ = scheduler.plan(.transcriptChanged, state: ready, now: start)
        _ = scheduler.plan(.timerFired, state: ready, now: start + .seconds(5))
        XCTAssertEqual(scheduler.plan(.evaluationFinished, state: ready, now: start + .seconds(12)),
                       [.cancelWake, .schedule(.milliseconds(1))])
        _ = scheduler.plan(.timerFired, state: ready, now: start + .seconds(12))
        var failure = ready; failure.failures = 1
        XCTAssertEqual(scheduler.plan(.evaluationFinished, state: failure, now: start + .seconds(13)),
                       [.cancelWake, .schedule(.seconds(9))])
        failure.failures = 20
        XCTAssertEqual(scheduler.plan(.evaluationFinished, state: failure, now: start + .seconds(13)),
                       [.cancelWake, .schedule(.seconds(59))])
    }

    func testStopOffUnavailableAndManualQuickCannotDispatchEvaluation() {
        for field in ["recording", "automatic", "available", "manualQuick"] {
            var scheduler = LiveSummaryScheduler(interval: .seconds(5))
            var state = ready
            if field == "recording" { state.recording = false }
            if field == "automatic" { state.automatic = false }
            if field == "available" { state.available = false }
            if field == "manualQuick" { state.manualQuick = true }
            XCTAssertFalse(scheduler.plan(.timerFired, state: state, now: start).contains(.evaluate))
        }
        var scheduler = LiveSummaryScheduler(interval: .seconds(5))
        XCTAssertEqual(scheduler.plan(.manualQuickStarted, state: ready, now: start), [.cancelWake, .cancelEvaluation])
    }

    func testCorrectionGraceIsBoundedEvenWithContinuousNewSpeech() {
        var scheduler = LiveSummaryScheduler(interval: .seconds(5))
        var state = ready; state.correctingSpeech = true
        _ = scheduler.plan(.transcriptChanged, state: state, now: start)
        for second in 1...6 {
            _ = scheduler.plan(.transcriptChanged, state: state, now: start + .seconds(second))
        }
        XCTAssertEqual(scheduler.plan(.timerFired, state: state, now: start + .seconds(7)), [.cancelWake, .evaluate])
    }

    func testEvaluationPlansPublicationAndRecommendationsWithoutAutomaticDeep() throws {
        let evaluation = try QuickSummaryDecision.parse(#"{"action":"publish","context":"Decision","bullets":["Monday"],"reviews":[]}"#)
        XCTAssertEqual(LiveSummaryScheduler.actions(for: evaluation), [.publishQuick("- Monday")])
        let keep = QuickSummaryDecision(action: "keep", context: "Options", bullets: [],
            reviews: [.init(mode: "deep", confidence: "high", reason: "Unresolved tradeoff")])
        XCTAssertEqual(LiveSummaryScheduler.actions(for: keep), [.keepQuick, .suggestReview(keep.reviews[0])])
    }
}
