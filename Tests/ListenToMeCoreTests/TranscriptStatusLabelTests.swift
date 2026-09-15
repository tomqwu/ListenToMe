import XCTest
@testable import ListenToMeCore

/// The transcript chip said "live" throughout the first-run speech-model download, when the session
/// is `isRunning` but no audio is flowing yet (#136/#147 review follow-up).
final class TranscriptStatusLabelTests: XCTestCase {

    func testIdleWhenNotRunningRegardlessOfAnythingElse() {
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: false, isPreparing: false, sources: 0), "idle")
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: false, isPreparing: false, sources: 2), "idle")
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: false, isPreparing: true, sources: 0), "idle")
    }

    func testPreparingNeverReadsAsLive() {
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: true, isPreparing: true, sources: 0), "preparing")
        // Even with a previous run's sources still in the store, nothing is being captured yet.
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: true, isPreparing: true, sources: 2), "preparing")
    }

    func testLiveCountsOnlyTheSourcesActuallyCaptured() {
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: true, isPreparing: false, sources: 0), "live")
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: true, isPreparing: false, sources: 1), "live · 1 src")
        XCTAssertEqual(TranscriptStatusLabel.text(isRunning: true, isPreparing: false, sources: 2), "live · 2 src")
    }
}
