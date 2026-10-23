import XCTest
@testable import ListenToMeCore

/// Apple Watch recording limits and transfer rules (issue #181, decision 5). The watch app compiles
/// `WatchCapturePolicy.swift` directly and has no test target, so its decisions are pinned here.
final class WatchCapturePolicyTests: XCTestCase {
    private let plenty: Int64 = 1_000_000_000

    func testStartNeedsTwentyPercentBattery() {
        XCTAssertEqual(WatchCapturePolicy.startBlock(battery: 0.19, freeBytes: plenty), .lowBattery)
        XCTAssertNil(WatchCapturePolicy.startBlock(battery: 0.20, freeBytes: plenty))
        XCTAssertNil(WatchCapturePolicy.startBlock(battery: 1, freeBytes: plenty))
    }

    func testStartNeedsTwoHundredMegabytesFree() {
        XCTAssertEqual(WatchCapturePolicy.startBlock(battery: 0.9, freeBytes: 199_999_999), .lowStorage)
        XCTAssertNil(WatchCapturePolicy.startBlock(battery: 0.9, freeBytes: 200_000_000))
        XCTAssertEqual(WatchCapturePolicy.startBlock(battery: 0.1, freeBytes: 0), .lowBattery, "Battery is named first")
    }

    /// Battery level -1 (monitoring off or unknown) and unreadable free space never block by themselves.
    func testUnknownBatteryOrStorageNeverBlocks() {
        XCTAssertNil(WatchCapturePolicy.startBlock(battery: -1, freeBytes: nil))
        XCTAssertNil(WatchCapturePolicy.startBlock(battery: -1, freeBytes: plenty))
        XCTAssertNil(WatchCapturePolicy.startBlock(battery: 0.5, freeBytes: nil))
        XCTAssertEqual(WatchCapturePolicy.startBlock(battery: -1, freeBytes: 10), .lowStorage)
    }

    func testStopsAtTenPercentAndAtThreeHours() {
        XCTAssertEqual(WatchCapturePolicy.stopTrigger(battery: 0.10, elapsed: 60), .lowBattery)
        XCTAssertEqual(WatchCapturePolicy.stopTrigger(battery: 0.05, elapsed: 60), .lowBattery)
        XCTAssertNil(WatchCapturePolicy.stopTrigger(battery: 0.11, elapsed: 60))
        XCTAssertEqual(WatchCapturePolicy.stopTrigger(battery: 0.5, elapsed: 10_800), .durationCap)
        XCTAssertNil(WatchCapturePolicy.stopTrigger(battery: 0.5, elapsed: 10_799))
        XCTAssertNil(WatchCapturePolicy.stopTrigger(battery: -1, elapsed: 10_799), "Unknown battery never stops")
        XCTAssertEqual(WatchCapturePolicy.stopTrigger(battery: -1, elapsed: 10_800), .durationCap)
        XCTAssertEqual(WatchCapturePolicy.stopTrigger(battery: 0.05, elapsed: 20_000), .durationCap)
    }

    func testRotatesEveryFiveMinutes() {
        XCTAssertEqual(WatchCapturePolicy.chunkDuration, 300)
        XCTAssertFalse(WatchCapturePolicy.shouldRotate(chunkElapsed: 299.99))
        XCTAssertTrue(WatchCapturePolicy.shouldRotate(chunkElapsed: 300))
        XCTAssertTrue(WatchCapturePolicy.shouldRotate(chunkElapsed: 301))
        XCTAssertLessThan(WatchCapturePolicy.chunkDuration, WatchChunkMetadata.maximumDuration,
                          "The phone accepts every chunk the watch makes")
    }

    func testRetryDelayDoublesFromThirtySecondsUpToHalfAnHour() {
        let delays = (0...8).map(WatchCapturePolicy.retryDelay(attempt:))
        XCTAssertEqual(delays, [30, 60, 120, 240, 480, 960, 1_800, 1_800, 1_800])
        XCTAssertEqual(WatchCapturePolicy.retryDelay(attempt: -3), 30)
        XCTAssertEqual(WatchCapturePolicy.retryDelay(attempt: Int.max), 1_800)
    }

    func testChunksToQueueAreTheFinalizedOnesNotAlreadyQueued() {
        let base = URL(fileURLWithPath: "/tmp/Outbox/A", isDirectory: true)
        let finalized = (0...3).map { base.appendingPathComponent("\($0).m4a") }
        let outstanding: Set<URL> = [finalized[1], URL(fileURLWithPath: "/tmp/Outbox/A/./sub/../3.m4a"),
                                     URL(fileURLWithPath: "/tmp/Outbox/B/0.m4a")]
        XCTAssertEqual(WatchCapturePolicy.chunksToQueue(finalized: finalized, outstanding: outstanding),
                       [finalized[0], finalized[2]])
        XCTAssertEqual(WatchCapturePolicy.chunksToQueue(finalized: [], outstanding: outstanding), [])
    }

    func testLimitCopy() {
        XCTAssertEqual(WatchCapturePolicy.text(for: StartBlock.lowBattery), "Charge Apple Watch above 20% to record.")
        XCTAssertEqual(WatchCapturePolicy.text(for: .lowStorage),
                       "Free up space on Apple Watch to record. 200 MB is needed.")
        XCTAssertEqual(WatchCapturePolicy.text(for: StopTrigger.lowBattery),
                       "Recording stopped: Apple Watch battery is at 10%. What was recorded is being sent to iPhone.")
        XCTAssertEqual(WatchCapturePolicy.text(for: .durationCap),
                       "Recording stopped at the 3-hour limit. What was recorded is being sent to iPhone.")
    }

    private typealias StartBlock = WatchCapturePolicy.StartBlock
    private typealias StopTrigger = WatchCapturePolicy.StopTrigger
}

/// What the watch publishes about its own recording, and how the phone and watch show it.
final class WatchCaptureStatusTests: XCTestCase {
    func testWatchStatusContextRoundTripsAndIgnoresOtherVersions() {
        let statuses = [
            WatchCaptureStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000.5),
                               waitingRecordings: 2),
            WatchCaptureStatus(state: .idle, startedAt: nil, waitingRecordings: 0),
        ]
        for status in statuses {
            let context = WatchLink.context(for: status)
            XCTAssertEqual(WatchLink.watchStatus(fromContext: context), status)
            XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
            XCTAssertNil(WatchLink.phoneStatus(fromContext: context), "A watch context is not a phone status")
        }
        var future = WatchLink.context(for: statuses[0])
        future["v"] = 2
        XCTAssertNil(WatchLink.watchStatus(fromContext: future))
        XCTAssertNil(WatchLink.watchStatus(fromContext: [:]))
        XCTAssertNil(WatchLink.watchStatus(fromContext: ["v": 1, "watch": ["state": "flying"]]))
        let phone = PhoneRecorderStatus(state: .idle, startedAt: nil, title: "A", lastStopReason: nil)
        XCTAssertNil(WatchLink.watchStatus(fromContext: WatchLink.context(for: phone)))
        let bare = WatchLink.watchStatus(fromContext: ["v": 1, "watch": ["state": "idle"]])
        XCTAssertEqual(bare, WatchCaptureStatus(state: .idle, startedAt: nil, waitingRecordings: 0))
    }

    func testWatchRecordingLine() {
        let now = Date(timeIntervalSince1970: 1_065)
        let recording = WatchCaptureStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                           waitingRecordings: 0)
        XCTAssertEqual(WatchRemoteText.watchRecordingLine(recording, now: now), "Apple Watch is recording · 01:05")
        let unstamped = WatchCaptureStatus(state: .recording, startedAt: nil, waitingRecordings: 0)
        XCTAssertEqual(WatchRemoteText.watchRecordingLine(unstamped, now: now), "Apple Watch is recording · 00:00")
        let idle = WatchCaptureStatus(state: .idle, startedAt: nil, waitingRecordings: 3)
        XCTAssertNil(WatchRemoteText.watchRecordingLine(idle, now: now))
        XCTAssertNil(WatchRemoteText.watchRecordingLine(nil, now: now))
    }

    /// No watch recording outlasts the 3-hour cap, so a "recording" status older than that is stale
    /// (the watch app was killed before it could publish idle) and is not shown.
    func testWatchRecordingLineIsHiddenOnceItOutlastsTheCap() {
        let startedAt = Date(timeIntervalSince1970: 0)
        let status = WatchCaptureStatus(state: .recording, startedAt: startedAt, waitingRecordings: 0)
        let atCap = startedAt.addingTimeInterval(WatchCapturePolicy.maximumDuration)
        XCTAssertEqual(WatchRemoteText.watchRecordingLine(status, now: atCap), "Apple Watch is recording · 3:00:00")
        let lastCheck = atCap.addingTimeInterval(WatchCapturePolicy.limitCheckInterval)
        XCTAssertNotNil(WatchRemoteText.watchRecordingLine(status, now: lastCheck))
        XCTAssertNil(WatchRemoteText.watchRecordingLine(status, now: lastCheck.addingTimeInterval(1)))
    }

    func testWaitingText() {
        XCTAssertNil(WatchRemoteText.waitingText(0))
        XCTAssertNil(WatchRemoteText.waitingText(-1))
        XCTAssertEqual(WatchRemoteText.waitingText(1), "1 recording waiting for iPhone")
        XCTAssertEqual(WatchRemoteText.waitingText(3), "3 recordings waiting for iPhone")
    }
}
