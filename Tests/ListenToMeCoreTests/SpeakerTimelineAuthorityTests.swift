import XCTest
@testable import ListenToMeCore

final class SpeakerTimelineAuthorityTests: XCTestCase {
    private func segment(_ id: String, _ start: Double, _ duration: Double) -> DiarizedSegment {
        DiarizedSegment(speakerId: id, start: start, duration: duration)
    }

    func testDelayedModelOutputPreservesLabelsBeyondItsConfirmedTime() {
        let history = [segment("a", 0, 10), segment("b", 10, 10)]
        let result = SpeakerStats.splice(history: history, window: [segment("c", 5, 10)],
                                         windowStart: 5, windowEnd: 15)
        XCTAssertEqual(result, [segment("a", 0, 5), segment("c", 5, 10), segment("b", 15, 5)])
    }

    func testConfirmedSilenceClearsOnlyItsOwnInterval() {
        let history = [segment("a", 0, 4), segment("b", 4, 4)]
        XCTAssertEqual(SpeakerStats.splice(history: history, window: [], windowStart: 2, windowEnd: 6),
                       [segment("a", 0, 2), segment("b", 6, 2)])
        XCTAssertEqual(SpeakerStats.splice(history: history, window: [], windowStart: 2), history,
                       "The legacy batch pipeline's empty-window policy is unchanged")
    }

    func testNoPredictionCanClaimAudioOutsideItsAuthority() {
        XCTAssertEqual(SpeakerStats.splice(history: [], window: [segment("new", 0, 100)],
                                           windowStart: 2, windowEnd: 4), [segment("new", 2, 2)])
        let history = [segment("a", 0, 4)]
        XCTAssertEqual(SpeakerStats.splice(history: history, window: [segment("new", 0, 100)],
                                           windowStart: 2, windowEnd: 2), history)
        XCTAssertEqual(SpeakerStats.splice(history: history, window: [], windowStart: 2, windowEnd: .nan), history)
        XCTAssertEqual(SpeakerStats.splice(history: [], window: [segment("bad", .nan, 2),
                                                                segment("bad", 0, .infinity)],
                                           windowStart: 0, windowEnd: 4), [])
    }
}
