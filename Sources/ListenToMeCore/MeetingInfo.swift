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

    /// A link with the parts that carry secrets removed — query, fragment and user info — keeping
    /// scheme, host and path. A meeting passcode travels in `?pwd=…`/`?context=…`, so importing the
    /// bare address says where the meeting is without handing out the way in. nil for a string that
    /// is not an absolute URL.
    public static func safeLink(_ url: URL) -> String? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme != nil, parts.host != nil else { return nil }
        parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        return parts.url?.absoluteString
    }

    /// Free invite text — an event's location or body — with every link reduced by `safeLink` and
    /// every e-mail address removed. This filters links and addresses only: other text, including
    /// dial-in numbers and meeting IDs, is left as written.
    public static func redactingLinksAndAddresses(_ text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return text
        }
        let redacted = NSMutableString(string: text)
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: redacted.length))
        for match in matches.reversed() {
            guard let url = match.url else { continue }
            // A detected address is a mailto: link, so removing those covers bare addresses too.
            let replacement = url.scheme?.lowercased() == "mailto" ? "" : (safeLink(url) ?? "")
            redacted.replaceCharacters(in: match.range, with: replacement)
        }
        // Removing an address can leave doubled spaces or a trailing space on its line.
        return (redacted as String).split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}
