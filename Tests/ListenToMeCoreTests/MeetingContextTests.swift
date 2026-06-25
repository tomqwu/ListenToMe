import XCTest
@testable import ListenToMeCore

final class MeetingContextTests: XCTestCase {
    private let fixedTime: (Date) -> String = { _ in "10:00" }

    func testTitleOnly() {
        let info = MeetingInfo(title: "Standup")
        XCTAssertEqual(MeetingContext.notes(for: info), "Meeting: Standup")
    }

    func testWithStartTimeOnly() {
        let info = MeetingInfo(title: "Standup", start: Date(timeIntervalSince1970: 0))
        let out = MeetingContext.notes(for: info, timeFormat: fixedTime)
        XCTAssertEqual(out, "Meeting: Standup\nTime: 10:00")
    }

    func testWithStartAndEndSpan() {
        let info = MeetingInfo(title: "Standup",
                               start: Date(timeIntervalSince1970: 0),
                               end: Date(timeIntervalSince1970: 3600))
        let out = MeetingContext.notes(for: info, timeFormat: fixedTime)
        XCTAssertEqual(out, "Meeting: Standup\nTime: 10:00 – 10:00")
    }

    func testOmitsEmptyLocationAttendeesAndNotes() {
        let info = MeetingInfo(title: "Standup", location: "",
                               attendees: [], notes: "   \n  ")
        XCTAssertEqual(MeetingContext.notes(for: info), "Meeting: Standup")
    }

    func testIncludesLocation() {
        let info = MeetingInfo(title: "Standup", location: "Room 4")
        XCTAssertEqual(MeetingContext.notes(for: info), "Meeting: Standup\nLocation: Room 4")
    }

    func testIncludesAttendeesAndNotes() {
        let info = MeetingInfo(
            title: "Planning",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3600),
            location: "Zoom",
            attendees: ["Alice", "Bob"],
            notes: "  Discuss roadmap.  "
        )
        let out = MeetingContext.notes(for: info, timeFormat: fixedTime)
        XCTAssertEqual(out, """
        Meeting: Planning
        Time: 10:00 – 10:00
        Location: Zoom
        Attendees: Alice, Bob

        Event notes:
        Discuss roadmap.
        """)
    }
}
