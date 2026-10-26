import EventKit
import Foundation
import OSLog
import ListenToMeCore

/// Reads the local macOS Calendar (via EventKit) to surface the user's current or next meeting.
/// Everything stays on-device; the only thing exposed to the rest of the app is a plain
/// `CalendarLookup`. This never throws or crashes: every failure mode is a distinct case, so the
/// caller can tell a denial (fixable in System Settings) from "no meeting right now" (issue #136).
enum CalendarService {
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe", category: "CalendarService")

    /// How far ahead to look for an upcoming meeting when nothing is happening right now.
    private static let lookaheadWindow: TimeInterval = 6 * 60 * 60

    /// Requests calendar access and returns the most relevant meeting, or the specific reason there
    /// isn't one (denied / no event / EventKit failure).
    static func currentOrNextMeeting(now: Date = Date(), requestAccess: Bool = true) async -> CalendarLookup {
        // Passive suggestions never trigger an OS permission prompt.
        guard requestAccess || EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .denied }
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = requestAccess ? try await store.requestFullAccessToEvents() : true
        } catch {
            log.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        guard granted else {
            log.info("Calendar access not granted")
            return .denied
        }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(lookaheadWindow),
            calendars: nil
        )
        let events = store.events(matching: predicate)
        guard let event = chooseEvent(from: events, now: now) else {
            log.info("No current or upcoming calendar meeting found")
            return .noMeeting
        }
        return .meeting(meetingInfo(from: event))
    }

    /// Picks the most recently started event happening now (start ≤ now < end), otherwise the soonest-starting
    /// upcoming event. Pure given the inputs, so it's straightforward to reason about.
    static func chooseEvent(from events: [EKEvent], now: Date) -> EKEvent? {
        // Skip all-day items (holidays, birthdays, OOO), canceled/free events, and meetings the
        // current user declined — none are the meeting the user wants context for.
        let meetings = events.filter { event in
            guard !event.isAllDay, event.status != .canceled, event.availability != .free else {
                return false
            }
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined {
                return false
            }
            return true
        }
        guard let index = MeetingSelection.currentOrNextIndex(
            in: meetings.map { (start: $0.startDate, end: $0.endDate) }, now: now
        ) else { return nil }
        return meetings[index]
    }

    /// Maps an `EKEvent` to the EventKit-free `MeetingInfo`.
    static func meetingInfo(from event: EKEvent) -> MeetingInfo {
        MeetingInfo(
            title: event.title ?? "(untitled meeting)",
            calendarID: event.eventIdentifier,
            start: event.startDate,
            end: event.endDate,
            location: event.location,
            attendees: event.attendees?.compactMap { $0.name } ?? [],
            notes: event.notes
        )
    }
}
