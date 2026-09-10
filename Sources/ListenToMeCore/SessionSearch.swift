import Foundation

/// A persisted past session for cross-meeting search.
public struct SessionRecord: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let date: Date
    public let transcript: String   // joined "You: …\nOthers: …" lines
    public let summary: String
    public let segments: [TranscriptSegment]?
    public let notes: String?
    public let quickSuggestion: String?
    public let deepAnswer: String?
    public let isComplete: Bool?
    public init(id: String, title: String, date: Date, transcript: String, summary: String,
                segments: [TranscriptSegment]? = nil, notes: String? = nil,
                quickSuggestion: String? = nil, deepAnswer: String? = nil, isComplete: Bool? = nil) {
        self.id = id; self.title = title; self.date = date
        self.transcript = transcript; self.summary = summary
        self.segments = segments; self.notes = notes
        self.quickSuggestion = quickSuggestion; self.deepAnswer = deepAnswer; self.isComplete = isComplete
    }
}

public enum SessionSearch {
    /// Records matching `query` (case-insensitive, all whitespace-split terms must appear across
    /// title+summary+transcript), ranked by total term frequency then most-recent date. An empty
    /// query returns all records sorted by date descending.
    public static func search(_ records: [SessionRecord], query: String) -> [SessionRecord] {
        let terms = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        if terms.isEmpty { return records.sorted { $0.date > $1.date } }
        func haystack(_ r: SessionRecord) -> String { "\(r.title)\n\(r.summary)\n\(r.transcript)".lowercased() }
        let scored: [(SessionRecord, Int)] = records.compactMap { record in
            let text = haystack(record)
            var score = 0
            for term in terms {
                let count = text.components(separatedBy: term).count - 1
                if count == 0 { return nil }   // every term must appear
                score += count
            }
            return (record, score)
        }
        return scored.sorted { ($0.1, $0.0.date) > ($1.1, $1.0.date) }.map(\.0)
    }
}
