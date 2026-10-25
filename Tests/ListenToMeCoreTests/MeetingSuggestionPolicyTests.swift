import XCTest
@testable import ListenToMeCore

final class MeetingSuggestionPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private func meeting(id: String? = "event", start: Double = 900, end: Double = 1100) -> MeetingInfo {
        MeetingInfo(title: "Meeting", calendarID: id, start: Date(timeIntervalSince1970: start),
                    end: Date(timeIntervalSince1970: end))
    }

    func testEligibilityRequiresOptInIdleAndCurrentEventAndGrantedLookup() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let policy = MeetingSuggestionPolicy(defaults: defaults)
        func choose(_ lookup: CalendarLookup, enabled: Bool = true, idle: Bool = true) -> MeetingInfo? {
            policy.suggestion(from: lookup, enabled: enabled, idleAndEmpty: idle, now: now)
        }
        XCTAssertEqual(choose(.meeting(meeting())), meeting())
        XCTAssertNil(choose(.meeting(meeting()), enabled: false))
        XCTAssertNil(choose(.meeting(meeting()), idle: false))
        XCTAssertNil(choose(.meeting(meeting(start: 1001))))
        XCTAssertNil(choose(.meeting(meeting(end: 1000))))
        XCTAssertNil(choose(.meeting(MeetingInfo(title: "Undated"))))
        XCTAssertNil(choose(.denied)); XCTAssertNil(choose(.noMeeting)); XCTAssertNil(choose(.failed("Denied")))
        XCTAssertEqual(choose(.meeting(meeting(start: 1000))), meeting(start: 1000))
    }

    func testDismissalSurvivesReloadButNotNextOccurrenceOrDifferentEvent() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let policy = MeetingSuggestionPolicy(defaults: defaults)
        policy.dismiss(meeting(), now: now)
        let restored = MeetingSuggestionPolicy(defaults: defaults)
        XCTAssertNil(restored.suggestion(from: .meeting(meeting()), enabled: true, idleAndEmpty: true, now: now))
        for other in [meeting(id: "other"), meeting(start: 950), meeting(id: nil)] {
            XCTAssertEqual(restored.suggestion(from: .meeting(other), enabled: true, idleAndEmpty: true, now: now), other)
        }
        let fallback = meeting(id: nil)
        policy.dismiss(fallback, now: now)
        XCTAssertNil(restored.suggestion(from: .meeting(fallback), enabled: true, idleAndEmpty: true, now: now))
    }

    func testDismissalsAreBoundedAndExpiredEntriesArePruned() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let policy = MeetingSuggestionPolicy(defaults: defaults)
        for index in 0..<110 { policy.dismiss(meeting(id: "\(index)", end: 1200 + Double(index)), now: now) }
        XCTAssertEqual(defaults.dictionary(forKey: "dismissedCalendarOccurrences")?.count, 100)
        policy.dismiss(meeting(), now: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(defaults.dictionary(forKey: "dismissedCalendarOccurrences")?.count, 1)
        policy.dismiss(MeetingInfo(title: "Undated"), now: now)
    }
}
