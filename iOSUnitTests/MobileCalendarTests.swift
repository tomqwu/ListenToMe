import EventKit
import ListenToMeCore
import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileCalendarTests: XCTestCase {
    func testReadAccessRequiresFullAccess() {
        XCTAssertEqual(MobileCalendar.access(for: .notDetermined), .notRequested)
        XCTAssertEqual(MobileCalendar.access(for: .fullAccess), .ready)
        XCTAssertEqual(MobileCalendar.access(for: .writeOnly), .denied)
        XCTAssertEqual(MobileCalendar.access(for: .denied), .denied)
        XCTAssertEqual(MobileCalendar.access(for: .restricted), .restricted)
    }

    func testCalendarMappingAndImportPreserveConversationAndPersistDetails() throws {
        let store = EKEventStore()
        let source = EKEvent(eventStore: store)
        source.title = "Release review"
        source.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        source.endDate = source.startDate.addingTimeInterval(3600)
        source.location = "Room 4"
        source.notes = "Review open actions."
        source.url = URL(string: "https://example.com/meeting")
        let event = MobileCalendar.event(source)
        XCTAssertTrue(event.context.contains("Release review"))
        XCTAssertTrue(event.context.contains("Room 4"))
        XCTAssertTrue(event.context.contains("Review open actions."))
        XCTAssertTrue(event.context.contains("https://example.com/meeting"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.title = "My conversation"
        session.notes = "Keep these notes."
        session.summary = "Keep summary"
        XCTAssertTrue(session.importCalendarEvent(event))
        XCTAssertEqual(session.title, "My conversation")
        XCTAssertTrue(session.notes.hasPrefix("Keep these notes.\n\nMeeting: Release review"))
        XCTAssertEqual(session.summary, "Keep summary")
        XCTAssertEqual(MobileSession(storageDirectory: root).notes, session.notes)
        session.newConversation()
        XCTAssertTrue(session.importCalendarEvent(event))
        XCTAssertEqual(session.title, "Release review")
        session.isSummarizing = true
        let notes = session.notes
        XCTAssertFalse(session.importCalendarEvent(event))
        XCTAssertEqual(session.notes, notes)
    }

    func testAllDayContextUsesCalendarDayRange() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Planning day"; event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: Date())
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)!
        event.endDate = nextDay.addingTimeInterval(-1)
        let first = MobileCalendar.event(event)
        XCTAssertTrue(first.context.contains("All-day event"))
        XCTAssertFalse(first.context.contains(nextDay.formatted(date: .abbreviated, time: .omitted)))
        XCTAssertFalse(first.context.contains(" – "))
    }

    /// Local opt-in fixture for the actual EventKit -> UI -> Notes journey. Never runs on a phone.
    func testStageOrRemoveCalendarUIFixture() async throws {
        #if targetEnvironment(simulator)
        let marker = URL.documentsDirectory.appendingPathComponent("CalendarUITestSeed")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Local Calendar UI fixture was not requested.")
        }
        let action = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let store = EKEventStore()
        XCTAssertEqual(EKEventStore.authorizationStatus(for: .event), .fullAccess)
        let calendarName = "ListenToMe isolated calendar UI fixture"
        for calendar in store.calendars(for: .event) where calendar.title == calendarName {
            try store.removeCalendar(calendar, commit: true)
        }
        if action == "create" {
            let local = try XCTUnwrap(store.sources.first { $0.sourceType == .local }, "Simulator needs a local calendar source")
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.source = local; calendar.title = calendarName
            try store.saveCalendar(calendar, commit: true)
            let event = EKEvent(eventStore: store)
            event.calendar = calendar; event.title = "ListenToMe Calendar UI Test"
            event.startDate = Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200)
            event.endDate = event.startDate.addingTimeInterval(1800)
            event.location = "Test room"; event.notes = "Calendar import acceptance fixture."
            event.url = URL(string: "https://example.com/calendar-test")
            try store.save(event, span: .thisEvent, commit: true)
            let calendarReader = MobileCalendar(store: store)
            await calendarReader.load(day: Date())
            XCTAssertTrue(calendarReader.events.contains { $0.meeting.title == event.title })
        }
        try FileManager.default.removeItem(at: marker)
        #else
        throw XCTSkip("Calendar fixtures are restricted to the simulator.")
        #endif
    }
}
