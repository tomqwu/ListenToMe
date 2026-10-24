import XCTest
@testable import ListenToMeCore

final class MeetingPaneBalanceTests: XCTestCase {
    func testBalanceAllocatesRequestedReadingSpace() {
        XCTAssertEqual(MeetingPaneBalance.balanced.transcriptWidth(available: 800), 400)
        XCTAssertEqual(MeetingPaneBalance.transcript.transcriptWidth(available: 800), 480)
        XCTAssertEqual(MeetingPaneBalance.quick.transcriptWidth(available: 800), 320)
    }

    func testNarrowPaneNeverSacrificesOtherPanesMinimum() {
        XCTAssertEqual(MeetingPaneBalance.transcript.transcriptWidth(available: 628), 348)
        XCTAssertEqual(MeetingPaneBalance.quick.transcriptWidth(available: 628), 280)
        for balance in MeetingPaneBalance.allCases {
            XCTAssertEqual(balance.transcriptWidth(available: 400), 200)
            XCTAssertEqual(balance.transcriptWidth(available: -1), 0)
        }
    }
}
