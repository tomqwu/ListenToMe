import XCTest
@testable import ListenToMeCore

final class CaptureTimelineTests: XCTestCase {
    func testDelayedTwoSourceBuffersRetainCaptureTimesAndGaps() {
        let microphone = CaptureTimeline.timestamp(capturedAt: 102, runStart: 100, deliveredAt: 120)
        let others = CaptureTimeline.timestamp(capturedAt: 108, runStart: 100, deliveredAt: 121)
        XCTAssertEqual(microphone, 2)
        XCTAssertEqual(others, 8)
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: 130, runStart: 100, deliveredAt: 140), 30)
        // Delayed/batched recognizer results carry their own range, independently of newest input.
        let first = CaptureTimeline.range(start: microphone, end: microphone + 1)
        let second = CaptureTimeline.range(start: others, end: others + 2)
        XCTAssertEqual(first.start, 2); XCTAssertEqual(first.end, 3)
        XCTAssertEqual(second.start, 8); XCTAssertEqual(second.end, 10)
    }

    func testRestartAndInvalidSourceClocks() {
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: 202, runStart: 200, deliveredAt: 220), 2)
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: nil, runStart: 100, deliveredAt: 103), 3)
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: 80, runStart: 100, deliveredAt: 103), 3)
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: 200, runStart: 100, deliveredAt: 103), 3)
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: .nan, runStart: 100, deliveredAt: 103), 3)
        XCTAssertEqual(CaptureTimeline.timestamp(capturedAt: nil, runStart: 100, deliveredAt: .infinity), 0)
    }

    func testInvalidOrSilentRecognitionRangesRemainUntimed() {
        for (start, end) in [(0.0, 0.0), (4, 2), (-1, 3), (.nan, 2), (1, .infinity)] {
            let range = CaptureTimeline.range(start: start, end: end)
            XCTAssertEqual(range.start, 0); XCTAssertEqual(range.end, 0)
        }
        XCTAssertEqual(CaptureTimeline.range(start: 0, end: 3).end, 3)
    }
}

final class TranscriptFollowStateTests: XCTestCase {
    func testGrowthWrappingAndResizeCannotStopFollowing() {
        var state = TranscriptFollowState()
        state.geometryChanged(atEnd: false)
        XCTAssertTrue(state.shouldScroll)
        state.geometryChanged(atEnd: true)
        XCTAssertTrue(state.following)
    }

    func testUserScrollFreezesAndLatestResumes() {
        var state = TranscriptFollowState()
        state.beginUserScroll()
        XCTAssertFalse(state.shouldScroll)
        state.geometryChanged(atEnd: false)
        state.endUserScroll(atEnd: false)
        XCTAssertFalse(state.following)
        state.geometryChanged(atEnd: true)
        XCTAssertFalse(state.following, "Programmatic geometry cannot resume history browsing")
        state.latest()
        XCTAssertTrue(state.shouldScroll)
    }

    func testUserReturningToEndResumesAndNewConversationResets() {
        var state = TranscriptFollowState()
        state.beginUserScroll(); state.geometryChanged(atEnd: false)
        state.geometryChanged(atEnd: true); state.endUserScroll(atEnd: true)
        XCTAssertTrue(state.shouldScroll)
        state.beginUserScroll(); state.endUserScroll(atEnd: false)
        state = TranscriptFollowState()
        XCTAssertTrue(state.shouldScroll)
    }
}
