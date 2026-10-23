import Foundation

/// One conversation as an Obsidian-friendly Markdown note: the file name to create it under and the
/// whole file's contents. Pure (no I/O, no clock), so the exact bytes are snapshot-tested.
public struct MarkdownVaultNote: Sendable, Equatable {
    /// The conversation ID the note belongs to.
    public let id: String
    /// The name a *new* note is created with. An existing note for the same conversation keeps the
    /// name it already has (see `MarkdownVault.marker(for:)`).
    public let fileName: String
    public let markdown: String

    public init(id: String, fileName: String, markdown: String) {
        self.id = id
        self.fileName = fileName
        self.markdown = markdown
    }
}

/// Formats saved conversations for a user-chosen Markdown folder or Obsidian vault (issue #53).
///
/// File names are keyed by the conversation ID, not the title: `2026-10-23 1430 ListenToMe 1a2b3c4d.md`.
/// Renaming a conversation, or a later checkpoint with a newer date, updates the same note instead
/// of creating a duplicate, and the name never collides with a note the user wrote themselves.
public enum MarkdownVault {
    /// The tag every note carries, so a vault can find them all.
    public static let tag = "listentome"

    public static func note(for record: SessionRecord, language: String? = nil,
                            timeZone: TimeZone = .current) -> MarkdownVaultNote {
        MarkdownVaultNote(id: record.id, fileName: fileName(id: record.id, date: record.date, timeZone: timeZone),
                          markdown: markdown(for: record, language: language, timeZone: timeZone))
    }

    /// A short, stable, filesystem-safe token for a conversation ID: the first eight hex digits of a
    /// UUID, or a hash for any other ID so two IDs with a shared prefix still differ.
    public static func key(for id: String) -> String {
        if let uuid = UUID(uuidString: id) { return String(uuid.uuidString.lowercased().prefix(8)) }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325   // FNV-1a, stable across launches unlike `hashValue`.
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return String(String(hash, radix: 16).leftPadded(to: 16).prefix(12))
    }

    /// The end of every note name for this conversation. The date in front of it is fixed when the
    /// note is first written, so the writer looks a note up by this marker alone.
    public static func marker(for id: String) -> String { "ListenToMe \(key(for: id)).md" }

    public static func fileName(id: String, date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
        return "\(day) \(time) \(marker(for: id))"
    }

    /// YAML front matter (date, duration, language, speakers, tags), then the summary, notes and
    /// the transcript with speaker names and timestamps where the recording has them.
    public static func markdown(for record: SessionRecord, language: String? = nil,
                                timeZone: TimeZone = .current) -> String {
        let segments = record.segments ?? []
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = timeZone
        dateFormatter.formatOptions = [.withInternetDateTime]

        var front = ["---", "title: \(yaml(singleLine(record.title)))",
                     "date: \(dateFormatter.string(from: record.date))"]
        if let duration = duration(of: segments) { front.append("duration: \(yaml(timestamp(duration)))") }
        if let language = language?.trimmingCharacters(in: .whitespaces), !language.isEmpty {
            front.append("language: \(yaml(Locale(identifier: language).identifier(.bcp47)))")
        }
        let names = speakers(in: segments)
        let speakerLines = names.map { "  - \(yaml($0))" }
        front.append(names.isEmpty ? "speakers: []" : (["speakers:"] + speakerLines).joined(separator: "\n"))
        front.append("tags:\n  - \(tag)")
        front.append("listentome_id: \(yaml(record.id))")
        front.append("---")

        var out = front.joined(separator: "\n") + "\n\n# \(singleLine(record.title))\n"
        func section(_ heading: String, _ body: String?) {
            let trimmed = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out += "\n## \(heading)\n\n\(trimmed)\n"
        }
        section("Summary", record.summary)
        section("Quick summary", record.quickSuggestion)
        section("Deep summary", record.deepAnswer)
        section("Notes", record.notes)
        section("Transcript", transcript(record))
        let attachments = (record.attachments ?? []).map { "- \(singleLine($0.name))" }
        section("Attachments", attachments.joined(separator: "\n"))
        return out
    }

    /// One line per segment. Timestamps are shown only when the recording carries timing; legacy
    /// records that kept only flattened text are written as they were saved.
    static func transcript(_ record: SessionRecord) -> String {
        guard let segments = record.segments, !segments.isEmpty else { return record.transcript }
        let timed = segments.contains { $0.start > 0 || $0.end > 0 }
        return segments.compactMap { segment -> String? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let stamp = timed ? "[\(timestamp(segment.start))] " : ""
            return "- \(stamp)**\(singleLine(segment.speakerLabel)):** \(singleLine(text))"
        }.joined(separator: "\n")
    }

    /// Speaker names in order of first appearance.
    static func speakers(in segments: [TranscriptSegment]) -> [String] {
        var seen = Set<String>()
        return segments.compactMap { segment in
            let name = singleLine(segment.speakerLabel)
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(name).inserted else { return nil }
            return name
        }
    }

    static func duration(of segments: [TranscriptSegment]) -> TimeInterval? {
        guard let first = segments.map(\.start).min(), let last = segments.map(\.end).max(),
              last > first else { return nil }
        return last - first
    }

    /// `12:05`, or `1:02:05` past an hour.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// A double-quoted YAML scalar: safe for colons, `#`, quotes and leading dashes in titles and names.
    static func yaml(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": continue
            default:
                if scalar.properties.generalCategory == .control { continue }
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
