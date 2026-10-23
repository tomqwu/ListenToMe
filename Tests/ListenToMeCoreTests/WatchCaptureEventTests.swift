import XCTest
@testable import ListenToMeCore

/// Review of #193 (issue #181): the audio system stopping the engine mid-recording, a watch status
/// that stopped being refreshed, and a Continue run whose first chunk was never finished.
final class WatchCaptureEventTests: XCTestCase {
    func testEventsThatStopCaptureEndTheRunWithAReasonAndContinue() {
        XCTAssertEqual(WatchCapturePolicy.stopReason(for: .interruptionBegan),
                       "Recording stopped by a call or Siri. Tap Continue to keep recording.")
        XCTAssertEqual(WatchCapturePolicy.stopReason(for: .mediaServicesReset),
                       "Recording stopped: Apple Watch restarted its audio. Tap Continue to keep recording.")
        let stopped = "Recording stopped: the Apple Watch microphone stopped. Tap Continue to keep recording."
        XCTAssertEqual(WatchCapturePolicy.stopReason(for: .engineConfigurationChanged(engineRunning: false)), stopped)
        XCTAssertEqual(WatchCapturePolicy.stopReason(for: .captureStopped), stopped)
        XCTAssertEqual(WatchCapturePolicy.stopReason(for: .routeChanged(inputAvailable: false)),
                       "Recording stopped: the Apple Watch microphone is not available. Tap Continue to keep "
                        + "recording.")
    }

    func testEventsThatLeaveCaptureRunningChangeNothing() {
        XCTAssertNil(WatchCapturePolicy.stopReason(for: .interruptionEnded))
        XCTAssertNil(WatchCapturePolicy.stopReason(for: .engineConfigurationChanged(engineRunning: true)))
        XCTAssertNil(WatchCapturePolicy.stopReason(for: .routeChanged(inputAvailable: true)))
    }

    func testRefreshedStatusRoundTripsItsStamp() {
        let status = WatchCaptureStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                        waitingRecordings: 0, updatedAt: Date(timeIntervalSince1970: 1_030.5))
        XCTAssertEqual(WatchLink.watchStatus(fromContext: WatchLink.context(for: status)), status)
        XCTAssertLessThan(WatchCaptureStatus.refreshInterval * 2, WatchCaptureStatus.staleAfter,
                          "One missed refresh is not enough to hide the line")
    }

    /// The watch republishes its status at every limit check; a recording status not refreshed for two
    /// minutes is stale (the watch app died or the link dropped) and is not shown on the phone.
    func testRecordingLineIsHiddenWhenTheWatchStopsRefreshingIt() {
        let refreshed = Date(timeIntervalSince1970: 1_000)
        let status = WatchCaptureStatus(state: .recording, startedAt: refreshed, waitingRecordings: 0,
                                        updatedAt: refreshed)
        XCTAssertEqual(WatchCaptureStatus.staleAfter, 120)
        XCTAssertNotNil(WatchRemoteText.watchRecordingLine(status, now: refreshed.addingTimeInterval(120)))
        XCTAssertNil(WatchRemoteText.watchRecordingLine(status, now: refreshed.addingTimeInterval(121)))
        let unstamped = WatchCaptureStatus(state: .recording, startedAt: refreshed, waitingRecordings: 0)
        XCTAssertNotNil(WatchRemoteText.watchRecordingLine(unstamped, now: refreshed.addingTimeInterval(600)),
                        "An older watch build without a stamp falls back to the 3-hour rule")
    }

    /// The watch names the lost chunk as the recording's last index, so a completed recording on the
    /// phone reopens, waits for it, then notes the gap and that the recording ended unexpectedly.
    func testAnUnfinishedFirstContinueChunkReopensACompletedRecordingWithAGap() {
        let id = UUID(), start = Date(timeIntervalSince1970: 1_700_000_000), hour: TimeInterval = 3_600
        var ledger = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        for index in 0...1 {
            ledger.receive(WatchChunkMetadata(recordingID: id, index: index, startOffset: Double(index) * 300,
                                              duration: 300, isLast: index == 1, startedAt: start, watchBuild: "28"),
                           at: start)
        }
        ledger.markTranscribed(through: 600)
        ledger.markCompleted()
        let arrived = start.addingTimeInterval(hour)
        ledger.receiveEnd(WatchRecordingEnd(recordingID: id, startedAt: start, lastIndex: 2, unexpected: true),
                          at: arrived)
        XCTAssertFalse(ledger.completed)
        XCTAssertTrue(ledger.endedUnexpectedly)
        XCTAssertEqual(ledger.nextBatch(now: arrived.addingTimeInterval(hour)),
                       WatchLedgerBatch(indices: [], newGaps: [], finishes: false), "Waits for the chunk")
        XCTAssertEqual(ledger.nextBatch(now: arrived.addingTimeInterval(25 * hour)),
                       WatchLedgerBatch(indices: [], newGaps: [2...2], finishes: true))
    }
}
