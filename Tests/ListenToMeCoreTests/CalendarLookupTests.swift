import XCTest
@testable import ListenToMeCore

/// Issue #136 (6): Load from Calendar left the conversation generically titled, and a denial was
/// indistinguishable from "no meeting right now".
final class CalendarLookupTests: XCTestCase {

    private let info = MeetingInfo(title: "Q3 pricing review", start: nil, end: nil,
                                   location: nil, attendees: [], notes: nil)

    func testAFoundMeetingHasNoBannerMessage() {
        XCTAssertNil(CalendarLookup.meeting(info).message)
        XCTAssertFalse(CalendarLookup.meeting(info).offersPrivacySettings)
    }

    func testDenialAndNoMeetingReadDifferentlyAndOnlyDenialIsActionable() {
        let denied = CalendarLookup.denied
        let none = CalendarLookup.noMeeting
        XCTAssertNotEqual(denied.message, none.message)
        XCTAssertTrue(try XCTUnwrap(denied.message).contains("Calendar access"))
        XCTAssertTrue(try XCTUnwrap(none.message).contains("No meeting"))
        XCTAssertTrue(denied.offersPrivacySettings)
        XCTAssertFalse(none.offersPrivacySettings)
    }

    func testAFailureCarriesTheReasonAndIsNotTreatedAsADenial() {
        let failed = CalendarLookup.failed("EKErrorDomain 4")
        XCTAssertTrue(try XCTUnwrap(failed.message).contains("EKErrorDomain 4"))
        XCTAssertFalse(failed.offersPrivacySettings)
    }
}
