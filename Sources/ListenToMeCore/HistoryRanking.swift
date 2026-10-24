import Foundation

/// A short excerpt of a conversation shown under a search result.
public struct HistorySnippet: Sendable, Equatable {
    public let source: HistorySource
    public let text: String
    public init(source: HistorySource, text: String) { self.source = source; self.text = text }
}

/// One conversation in the History search results.
public struct HistorySearchResult: Sendable, Equatable, Identifiable {
    public var id: String { record.id }
    public let record: SessionRecord
    /// Every query word appears in the conversation (the keyword search that predates #57).
    public let matchesWords: Bool
    /// The on-device embeddings found a passage about the same thing, possibly in other words.
    public let isRelated: Bool
    public let snippet: HistorySnippet?
    public init(record: SessionRecord, matchesWords: Bool, isRelated: Bool, snippet: HistorySnippet?) {
        self.record = record; self.matchesWords = matchesWords; self.isRelated = isRelated; self.snippet = snippet
    }
}

/// Hybrid ranking: the keyword order and the semantic order are fused with reciprocal-rank fusion,
/// so a conversation found both ways comes first, and a conversation found only by meaning can sit
/// between weak keyword hits. Every keyword match is kept; semantic-only matches are bounded.
public enum HistoryRanking {
    /// Calibrated on Apple's English word vectors (`NaturalLanguageEmbedderTests`): paraphrases of a
    /// passage scored 0.51–0.68 and stood 0.15–0.30 above the typical passage; unrelated questions
    /// stayed below 0.5. The gap is the second guard, for an archive where everything is similar.
    public struct Parameters: Sendable, Equatable {
        /// Cosine similarity a passage needs before it can make its conversation "related".
        public var floor: Float
        /// …and how far it must stand above the typical (mean) passage for the same query, so a
        /// query that is a little similar to everything relates to nothing.
        public var minimumGap: Float
        /// With fewer passages than this there is no reliable "typical"; the floor rises instead.
        public var gapSample: Int
        public var smallSampleFloor: Float
        /// Semantic-only results must be within this distance of the best passage found.
        public var margin: Float
        /// At most this many conversations are added by meaning alone.
        public var maxRelated: Int
        /// The reciprocal-rank-fusion constant (60 is the value from the original RRF paper).
        public var fusion: Double
        public init(floor: Float = 0.5, minimumGap: Float = 0.1, gapSample: Int = 5, smallSampleFloor: Float = 0.55,
                    margin: Float = 0.08, maxRelated: Int = 8, fusion: Double = 60) {
            self.floor = floor; self.minimumGap = minimumGap; self.gapSample = gapSample
            self.smallSampleFloor = smallSampleFloor; self.margin = margin; self.maxRelated = maxRelated
            self.fusion = fusion
        }

        /// Whether a passage scoring `score` is relevant, given the mean score of the `sample`
        /// passages compared with the same query.
        func isRelevant(_ score: Float, typical: Float, sample: Int) -> Bool {
            sample < gapSample ? score >= max(floor, smallSampleFloor)
                : score >= floor && score - typical >= minimumGap
        }
    }

    /// Semantic candidates worth showing, best first: relevant, and close to the best one.
    static func related(_ best: [(id: String, score: Float)], typical: Float, sample: Int,
                        parameters: Parameters) -> [(id: String, score: Float)] {
        let ordered = best.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        guard let top = ordered.first?.score else { return [] }
        return ordered.filter {
            parameters.isRelevant($0.score, typical: typical, sample: sample) && $0.score >= top - parameters.margin
        }
    }

    /// Fuses two rankings of conversation IDs. Ties go to keyword matches, then to keyword order.
    static func fuse(keyword: [String], semantic: [String], fusion: Double) -> [String] {
        var keywordRank: [String: Int] = [:]
        for (rank, id) in keyword.enumerated() where keywordRank[id] == nil { keywordRank[id] = rank }
        var semanticRank: [String: Int] = [:]
        for (rank, id) in semantic.enumerated() where semanticRank[id] == nil { semanticRank[id] = rank }
        func score(_ id: String) -> Double {
            (keywordRank[id].map { 1 / (fusion + Double($0) + 1) } ?? 0)
                + (semanticRank[id].map { 1 / (fusion + Double($0) + 1) } ?? 0)
        }
        let ids = Array(keywordRank.keys) + semanticRank.keys.filter { keywordRank[$0] == nil }
        return ids.sorted { lhs, rhs in
            let (left, right) = (score(lhs), score(rhs))
            if left != right { return left > right }
            let (leftWord, rightWord) = (keywordRank[lhs], keywordRank[rhs])
            if (leftWord != nil) != (rightWord != nil) { return leftWord != nil }
            if let leftWord, let rightWord, leftWord != rightWord { return leftWord < rightWord }
            return (semanticRank[lhs] ?? .max, lhs) < (semanticRank[rhs] ?? .max, rhs)
        }
    }

    static let matching: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// The keyword snippet: from the part of the conversation where most query words occur
    /// (summary, then notes, then transcript on a tie), centred on the first occurrence.
    static func keywordSnippet(_ record: SessionRecord, terms: [String], limit: Int = 200) -> HistorySnippet? {
        let parts: [(HistorySource, String)] = [
            (.summary, record.summary),
            (.notes, record.notes ?? ""),
            (.transcript, HistoryChunker.transcriptUnits(record).joined(separator: " "))
        ]
        struct Hit { let source: HistorySource; let text: String; let first: Range<String.Index>; let found: Int }
        var best: Hit?
        for (source, text) in parts where !text.isEmpty {
            let ranges = terms.compactMap { text.range(of: $0, options: matching) }
            guard let first = ranges.min(by: { $0.lowerBound < $1.lowerBound }) else { continue }
            guard ranges.count > best?.found ?? 0 else { continue }
            best = Hit(source: source, text: text, first: first, found: ranges.count)
        }
        guard let best else { return nil }
        return HistorySnippet(source: best.source, text: excerpt(best.text, around: best.first, limit: limit))
    }

    /// Up to `limit` characters of `text` around `range`, with ellipses where it was cut.
    static func excerpt(_ text: String, around range: Range<String.Index>, limit: Int) -> String {
        let flat = String(text.map { $0.isNewline ? " " : $0 })   // same Character count as `text`
        guard flat.count > limit else { return flat }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        let start = max(0, min(offset - limit / 3, flat.count - limit))
        let lower = flat.index(flat.startIndex, offsetBy: start)
        let upper = flat.index(lower, offsetBy: limit)
        var result = String(flat[lower..<upper]).trimmingCharacters(in: .whitespaces)
        if start > 0 { result = "…" + result }
        if upper < flat.endIndex { result += "…" }
        return result
    }

    /// A passage shortened for display.
    static func clipped(_ text: String, limit: Int = 200) -> String {
        text.count > limit ? String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : text
    }
}
