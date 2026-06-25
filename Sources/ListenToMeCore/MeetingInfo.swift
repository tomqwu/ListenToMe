import Foundation

/// Plain meeting metadata (from a calendar event), independent of EventKit so it's testable.
public struct MeetingInfo: Sendable, Equatable {
    public let title: String
    public let start: Date?
    public let end: Date?
    public let location: String?
    public let attendees: [String]
    public let notes: String?
    public init(title: String, start: Date? = nil, end: Date? = nil,
                location: String? = nil, attendees: [String] = [], notes: String? = nil) {
        self.title = title; self.start = start; self.end = end
        self.location = location; self.attendees = attendees; self.notes = notes
    }
}

public enum MeetingContext {
    /// Formats meeting info into a Context-notes scaffold. Omits empty fields. `now`/formatting
    /// is injected for deterministic tests.
    public static func notes(for info: MeetingInfo,
                             timeFormat: (Date) -> String = { "\($0)" }) -> String {
        var lines = ["Meeting: \(info.title)"]
        if let start = info.start {
            let span = info.end.map { "\(timeFormat(start)) – \(timeFormat($0))" } ?? timeFormat(start)
            lines.append("Time: \(span)")
        }
        if let location = info.location, !location.isEmpty { lines.append("Location: \(location)") }
        if !info.attendees.isEmpty { lines.append("Attendees: \(info.attendees.joined(separator: ", "))") }
        if let notes = info.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Event notes:")
            lines.append(notes.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
    }
}
