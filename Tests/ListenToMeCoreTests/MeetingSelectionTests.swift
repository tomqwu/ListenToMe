import XCTest
@testable import ListenToMeCore

final class MeetingSelectionTests: XCTestCase {
    private func date(_ hour: Double) -> Date { Date(timeIntervalSince1970: hour * 3600) }

    func testStandupWinsOverAnOverlappingBusyBlock() {
        let times = [(start: date(9), end: date(17)), (start: date(10), end: date(10.5))]
        XCTAssertEqual(MeetingSelection.currentOrNextIndex(in: times, now: date(10.1)), 1)
        XCTAssertEqual(MeetingSelection.currentOrNextIndex(in: times.reversed(), now: date(10.1)), 0)
    }

    func testBackToBackAndEndBoundaryDoNotSelectTheFinishedMeeting() {
        let times = [(start: date(9), end: date(10)), (start: date(10), end: date(11))]
        XCTAssertEqual(MeetingSelection.currentOrNextIndex(in: times, now: date(10)), 1)
        XCTAssertNil(MeetingSelection.currentOrNextIndex(in: times, now: date(11)))
    }

    func testSoonestUpcomingAndMissingDates() {
        let times: [(start: Date?, end: Date?)] = [(nil, nil), (date(12), date(13)), (date(11), date(12))]
        XCTAssertEqual(MeetingSelection.currentOrNextIndex(in: times, now: date(10)), 2)
        XCTAssertNil(MeetingSelection.currentOrNextIndex(in: [], now: date(10)))
    }
}
