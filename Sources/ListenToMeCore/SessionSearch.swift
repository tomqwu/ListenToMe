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
    public let attachments: [SessionAttachment]?
    public let sourceImportID: String?
    public init(id: String, title: String, date: Date, transcript: String, summary: String,
                segments: [TranscriptSegment]? = nil, notes: String? = nil,
                quickSuggestion: String? = nil, deepAnswer: String? = nil, isComplete: Bool? = nil,
                attachments: [SessionAttachment]? = nil, sourceImportID: String? = nil) {
        self.id = id; self.title = title; self.date = date
        self.transcript = transcript; self.summary = summary
        self.segments = segments; self.notes = notes
        self.quickSuggestion = quickSuggestion; self.deepAnswer = deepAnswer; self.isComplete = isComplete
        self.attachments = attachments; self.sourceImportID = sourceImportID
    }
}

public enum SessionSearch {
    /// Case-, diacritic- and width-insensitive form used on both sides of every comparison, so
    /// "cafe" matches "café", "zurich" matches "Zürich" and "ai" matches full-width "ＡＩ".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Searchable text of a record. Built from segment text (plus speaker names) when segments are
    /// available, so the "You:"/"Others:" prefixes of the flattened transcript cannot create false
    /// matches; notes are included because iOS share-sheet imports land there.
    static func haystack(_ record: SessionRecord) -> String {
        var parts = [record.title, record.summary, record.notes ?? ""]
        if let segments = record.segments, !segments.isEmpty {
            for segment in segments {
                parts.append(segment.speakerName ?? "")
                parts.append(segment.text)
            }
        } else {
            parts.append(record.transcript)
        }
        return fold(parts.joined(separator: "\n"))
    }

    /// Occurrences of `term` in `text`, split into whole-word hits (nothing alphanumeric on either
    /// side) and hits inside a longer word. Scripts without word separators (CJK) naturally produce
    /// in-word hits, so both kinds count as a match — only the ranking differs.
    static func occurrences(of term: String, in text: String) -> (whole: Int, total: Int) {
        guard !term.isEmpty else { return (0, 0) }
        var whole = 0, total = 0
        var start = text.startIndex
        while start < text.endIndex, let range = text.range(of: term, range: start..<text.endIndex) {
            total += 1
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            func isWordCharacter(_ character: Character?) -> Bool {
                guard let character else { return false }
                return character.isLetter || character.isNumber
            }
            if !isWordCharacter(before) && !isWordCharacter(after) { whole += 1 }
            start = range.lowerBound < range.upperBound ? range.upperBound : text.index(after: range.lowerBound)
        }
        return (whole, total)
    }

    /// Records matching `query` (case-, diacritic- and width-insensitive; terms are split on any
    /// whitespace and every term must appear across title + summary + notes + transcript/segments),
    /// ranked by whole-word hits, then total hits, then most-recent date. An empty query returns all
    /// records sorted by date descending.
    public static func search(_ records: [SessionRecord], query: String) -> [SessionRecord] {
        let terms = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.isEmpty { return records.sorted { $0.date > $1.date } }
        let scored: [(record: SessionRecord, whole: Int, total: Int)] = records.compactMap { record in
            let text = haystack(record)
            var whole = 0, total = 0
            for term in terms {
                let counts = occurrences(of: term, in: text)
                if counts.total == 0 { return nil }   // every term must appear
                whole += counts.whole
                total += counts.total
            }
            return (record, whole, total)
        }
        return scored
            .sorted { ($0.whole, $0.total, $0.record.date) > ($1.whole, $1.total, $1.record.date) }
            .map(\.record)
    }
}
