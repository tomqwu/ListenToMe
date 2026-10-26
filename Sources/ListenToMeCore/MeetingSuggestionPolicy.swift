import Foundation

/// Eligibility and bounded, persistent dismissal of calendar occurrences. Never starts capture.
public struct MeetingSuggestionPolicy {
    private let defaults: UserDefaults
    private static let key = "dismissedCalendarOccurrences"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func identity(_ meeting: MeetingInfo) -> String {
        "\(meeting.calendarID ?? meeting.title)|\(meeting.start?.timeIntervalSince1970 ?? 0)"
    }

    public func suggestion(from lookup: CalendarLookup, enabled: Bool, idleAndEmpty: Bool,
                           now: Date) -> MeetingInfo? {
        guard enabled, idleAndEmpty, case .meeting(let meeting) = lookup,
              let start = meeting.start, let end = meeting.end, start <= now, now < end else { return nil }
        let dismissed = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        guard dismissed[identity(meeting)] == nil else { return nil }
        return meeting
    }

    public func dismiss(_ meeting: MeetingInfo, now: Date) {
        var dismissed = (defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:])
            .filter { $0.value > now.timeIntervalSince1970 }
        dismissed[identity(meeting)] = meeting.end?.timeIntervalSince1970 ?? now.timeIntervalSince1970
        // Keep the most recently ending occurrences; no invite body or participant data is stored.
        dismissed = Dictionary(uniqueKeysWithValues: dismissed.sorted { $0.value > $1.value }.prefix(100).map { ($0.key, $0.value) })
        defaults.set(dismissed, forKey: Self.key)
    }
}
