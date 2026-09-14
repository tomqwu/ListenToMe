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

    /// #125: an imported invite becomes notes that every summary sends to the selected provider, so a
    /// join secret or an e-mail address inside the body or the location must not survive the import.
    func testSafeLinkAndRedactionStripJoinSecretsAndAddressesFromInviteText() {
        XCTAssertEqual(MeetingContext.safeLink(URL(string: "https://zoom.us/j/1?pwd=x#ok")!), "https://zoom.us/j/1")
        XCTAssertEqual(MeetingContext.safeLink(URL(string: "https://u:p@teams.example.com/m/9")!),
                       "https://teams.example.com/m/9")
        XCTAssertNil(MeetingContext.safeLink(URL(string: "relative/path")!))

        let invite = """
        Join Zoom Meeting
        https://example.zoom.us/j/98765432101?pwd=QWxpY2VTZWNyZXQ

        Meeting ID: 987 6543 2101
        Questions? Write to alice@example.com or mailto:bob@example.com
        """
        let clean = MeetingContext.redactingLinksAndAddresses(invite)
        XCTAssertTrue(clean.contains("https://example.zoom.us/j/98765432101"), clean)
        XCTAssertFalse(clean.contains("pwd="), clean)
        XCTAssertFalse(clean.contains("QWxpY2VTZWNyZXQ"), clean)
        XCTAssertFalse(clean.contains("@example.com"), clean)
        XCTAssertTrue(clean.contains("Join Zoom Meeting"), "Non-sensitive text is kept: \(clean)")
        XCTAssertTrue(clean.contains("Meeting ID: 987 6543 2101"),
                      "Only links and addresses are filtered; nothing else is claimed: \(clean)")

        let location = MeetingContext.redactingLinksAndAddresses(
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc?context=%7b%22Tid%22%3a%22secret%22%7d")
        XCTAssertEqual(location, "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc")
        XCTAssertEqual(MeetingContext.redactingLinksAndAddresses("Room 4"), "Room 4")
    }
}
