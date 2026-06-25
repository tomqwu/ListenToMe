import EventKit
import Foundation
import OSLog
import ListenToMeCore

/// Reads the local macOS Calendar (via EventKit) to surface the user's current or next meeting.
/// Everything stays on-device; the only thing exposed to the rest of the app is a plain
/// `MeetingInfo`. Access failures and "no event" both degrade to `nil` — this never throws or crashes.
enum CalendarService {
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe", category: "CalendarService")

    /// How far ahead to look for an upcoming meeting when nothing is happening right now.
    private static let lookaheadWindow: TimeInterval = 6 * 60 * 60

    /// Requests calendar access and returns the most relevant meeting, or `nil` if access was
    /// denied or no suitable event exists.
    static func currentOrNextMeeting(now: Date = Date()) async -> MeetingInfo? {
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            log.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard granted else {
            log.info("Calendar access not granted")
            return nil
        }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(lookaheadWindow),
            calendars: nil
        )
        let events = store.events(matching: predicate)
        guard let event = chooseEvent(from: events, now: now) else {
            log.info("No current or upcoming calendar meeting found")
            return nil
        }
        return meetingInfo(from: event)
    }

    /// Picks an event happening now (start ≤ now ≤ end) if any, otherwise the soonest-starting
    /// upcoming event. Pure given the inputs, so it's straightforward to reason about.
    static func chooseEvent(from events: [EKEvent], now: Date) -> EKEvent? {
        let inProgress = events
            .filter { event in
                guard let start = event.startDate, let end = event.endDate else { return false }
                return start <= now && now <= end
            }
            .min { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        if let inProgress { return inProgress }

        return events
            .filter { ($0.startDate ?? .distantPast) > now }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    /// Maps an `EKEvent` to the EventKit-free `MeetingInfo`.
    static func meetingInfo(from event: EKEvent) -> MeetingInfo {
        MeetingInfo(
            title: event.title ?? "(untitled meeting)",
            start: event.startDate,
            end: event.endDate,
            location: event.location,
            attendees: event.attendees?.compactMap { $0.name } ?? [],
            notes: event.notes
        )
    }
}
