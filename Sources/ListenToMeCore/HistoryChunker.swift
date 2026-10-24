import Foundation

/// Which part of a saved conversation a passage came from.
public enum HistorySource: String, Sendable, Codable, CaseIterable {
    case summary, notes, transcript

    public var label: String {
        switch self {
        case .summary: return "Summary"
        case .notes: return "Notes"
        case .transcript: return "Transcript"
        }
    }
}

/// One searchable passage of a saved conversation. `ordinal` is its position in the record's
/// chunk list, which is what the semantic index stores instead of the text itself.
public struct HistoryChunk: Sendable, Equatable {
    public let source: HistorySource
    public let ordinal: Int
    public let text: String
    /// The transcription language of every line in the passage (#206), when the record says and all
    /// its lines agree; nil for summaries, notes and older records, whose language is detected.
    public let language: String?
    public init(source: HistorySource, ordinal: Int, text: String, language: String? = nil) {
        self.source = source; self.ordinal = ordinal; self.text = text; self.language = language
    }
}

/// Splits a conversation's summary, notes and transcript into short passages for the semantic
/// index and for snippets. Deterministic: the same record always yields the same chunks, so the
/// index can keep only vectors and ordinals and recover the text from the archive on demand.
public enum HistoryChunker {
    /// About three spoken sentences: long enough to carry a topic, short enough to read as a snippet.
    public static let targetCharacters = 360
    /// Bounds the work and the index size for one very long conversation. Longer conversations
    /// get proportionally longer passages instead of more of them.
    public static let maxChunksPerRecord = 160

    public static func chunks(for record: SessionRecord) -> [HistoryChunk] {
        let sources: [(HistorySource, [Unit])] = [
            (.summary, lines(record.summary).map { Unit(text: $0, language: nil) }),
            (.notes, lines(record.notes ?? "").map { Unit(text: $0, language: nil) }),
            (.transcript, transcriptLines(record))
        ]
        var target = targetCharacters
        while true {
            var result: [HistoryChunk] = []
            for (source, units) in sources {
                for unit in pack(units, target: target) {
                    result.append(HistoryChunk(source: source, ordinal: result.count, text: unit.text,
                                               language: unit.language))
                }
            }
            if result.count <= maxChunksPerRecord { return result }
            target *= 2
        }
    }

    /// Stable 64-bit FNV-1a over the chunk texts. Swift's `Hasher` is seeded per launch, so it
    /// cannot tell whether a record on disk still matches the vectors stored for it.
    public static func fingerprint(_ chunks: [HistoryChunk], salt: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ text: String) {
            for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
            hash = (hash ^ 0x1f) &* 0x0000_0100_0000_01b3
        }
        mix(salt)
        for chunk in chunks { mix(chunk.source.rawValue); mix(chunk.language ?? ""); mix(chunk.text) }
        return hash
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Segment text without the "You:"/"Others:" prefixes, which carry no meaning to embed.
    static func transcriptUnits(_ record: SessionRecord) -> [String] { transcriptLines(record).map(\.text) }

    struct Unit: Equatable { let text: String; let language: String? }

    static func transcriptLines(_ record: SessionRecord) -> [Unit] {
        if let segments = record.segments, !segments.isEmpty {
            return segments.compactMap { segment in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : Unit(text: text, language: segment.language)
            }
        }
        return lines(record.transcript).map { Unit(text: $0, language: nil) }
    }

    /// Greedy packing of whole units up to `target` characters; a single unit longer than twice the
    /// target is split at whitespace (or at a character count for scripts without spaces). A change
    /// of transcription language starts a new passage, so each passage has one language.
    static func pack(_ units: [Unit], target: Int) -> [Unit] {
        var result: [Unit] = []
        var current = ""
        var language: String?
        func flush() { if !current.isEmpty { result.append(Unit(text: current, language: language)); current = "" } }
        for unit in units {
            for piece in split(unit.text, limit: target * 2) {
                if !current.isEmpty && (current.count + 1 + piece.count > target || unit.language != language) { flush() }
                if current.isEmpty { language = unit.language }
                current = current.isEmpty ? piece : current + " " + piece
            }
        }
        flush()
        return result
    }

    static func split(_ unit: String, limit: Int) -> [String] {
        guard unit.count > limit else { return [unit] }
        var pieces: [String] = []
        var rest = Substring(unit)
        while rest.count > limit {
            let window = rest.prefix(limit)
            let cut = window.lastIndex(where: \.isWhitespace).flatMap { $0 > window.startIndex ? $0 : nil }
                ?? window.endIndex
            pieces.append(String(rest[..<cut]).trimmingCharacters(in: .whitespaces))
            rest = rest[cut...].drop(while: \.isWhitespace)
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces.filter { !$0.isEmpty }
    }
}
