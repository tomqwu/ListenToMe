import EventKit
import Foundation
import ListenToMeCore
import Observation

struct MobileCalendarEvent: Identifiable {
    let id: String
    let meeting: MeetingInfo
    let calendarName: String
    let allDay: Bool
    let url: URL?

    var context: String {
        var contextMeeting = meeting
        if allDay, let start = meeting.start, let end = meeting.end, end > start {
            let lastDay = end.addingTimeInterval(-1)
            contextMeeting = MeetingInfo(title: meeting.title, start: start,
                end: Calendar.current.isDate(start, inSameDayAs: lastDay) ? nil : lastDay,
                location: meeting.location, attendees: meeting.attendees, notes: meeting.notes)
        }
        var text = MeetingContext.notes(for: contextMeeting) { date in
            date.formatted(date: .abbreviated, time: allDay ? .omitted : .shortened)
        }
        if allDay { text += "\nAll-day event" }
        if let link = url.flatMap(Self.link) { text += "\nEvent link: \(link)" }
        return text
    }

    /// Imported details become part of the notes every summary sends to the selected provider, so the
    /// link is reduced to where the meeting is, never how to join it: a join URL's query and fragment
    /// carry the passcode (`?pwd=…`) and any user info carries credentials.
    static func link(_ url: URL) -> String? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme != nil,
              parts.host != nil else { return nil }
        parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        return parts.url?.absoluteString
    }
}

@MainActor @Observable
final class MobileCalendar {
    enum Access { case notRequested, ready, denied, restricted }
    var access = Access.notRequested
    var events: [MobileCalendarEvent] = []
    var loading = false
    var message: String?
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) { self.store = store }

    static func access(for status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: return .ready
        case .denied, .writeOnly: return .denied
        case .restricted: return .restricted
        default: return .notRequested
        }
    }

    func load(day: Date, requestAccess: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        events = []; message = nil
        do {
            if requestAccess, Self.access(for: EKEventStore.authorizationStatus(for: .event)) == .notRequested {
                _ = try await store.requestFullAccessToEvents()
            }
            access = Self.access(for: EKEventStore.authorizationStatus(for: .event))
            guard access == .ready else { return }
            let start = Calendar.current.startOfDay(for: day)
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: predicate)
                .filter { $0.status != .canceled }
                .sorted { $0.startDate < $1.startDate }
                .map(Self.event)
        } catch { message = "Could not read Calendar: \(error.localizedDescription)" }
    }

    /// Names only, as macOS does (App/CalendarService.swift): an attendee with no display name is
    /// left out rather than published as an e-mail address in notes sent to the selected provider.
    /// EventKit reports the address itself as `name` for an unnamed invitee, hence the "@" check.
    static func attendeeNames(_ names: [String?]) -> [String] {
        names.compactMap { name in
            let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.contains("@") ? nil : trimmed
        }
    }

    static func event(_ event: EKEvent) -> MobileCalendarEvent {
        let people = attendeeNames((event.attendees ?? []).map(\.name))
        let meeting = MeetingInfo(title: event.title ?? "Untitled event", start: event.startDate,
                                  end: event.endDate, location: event.location, attendees: people, notes: event.notes)
        // Include occurrence time so recurring events do not share a row identity.
        let id = (event.eventIdentifier ?? UUID().uuidString) + "-" + String(event.startDate.timeIntervalSince1970)
        return MobileCalendarEvent(id: id, meeting: meeting, calendarName: event.calendar?.title ?? "Calendar",
                                   allDay: event.isAllDay, url: event.url)
    }
}

extension MobileSession {
    @discardableResult
    func importCalendarEvent(_ event: MobileCalendarEvent) -> Bool {
        guard !isSummarizing else {
            message = "Wait for the current summary to finish before importing calendar details."
            return false
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == "New conversation" {
            title = event.meeting.title
        }
        notes += (notes.isEmpty ? "" : "\n\n") + event.context
        guard save(announce: false) else { return false }
        message = "Calendar details added to Notes."
        return true
    }
}
