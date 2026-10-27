import Foundation
import Observation

/// Optional translation of a completed summary. Originals and AI provider settings never change.
@MainActor @Observable public final class SummaryTranslationCoordinator {
    public let worker: LiveTranslationCoordinator
    public private(set) var source = ""
    public private(set) var targetLanguage = "en"
    public private(set) var isRequested = false
    public private(set) var isGenerating = false
    private var conversationID: String?
    private struct Piece {
        let original: String
        let prefix: String
        let suffix: String
        let segments: [TranscriptSegment]
    }
    private var pieces: [Piece] = []

    public init(translator: (any TranscriptTranslating)? = nil) { worker = .init(translator: translator) }

    public func update(source: String, conversationID: String, target: String, isGenerating: Bool = false) {
        let newConversation = self.conversationID != conversationID
        let rebuild = self.source != source || newConversation || (self.isGenerating && !isGenerating)
        if newConversation { isRequested = false; worker.reset() }
        self.conversationID = conversationID; self.source = source
        targetLanguage = target; self.isGenerating = isGenerating
        if isGenerating { pieces = [] }
        else if rebuild { pieces = source.count <= 100_000 ? Self.split(source) : [] }
        feed()
    }

    public func matches(source: String, conversationID: String, target: String) -> Bool {
        self.source == source && self.conversationID == conversationID && targetLanguage == target
    }

    public func request() {
        guard canTranslate else { return }
        isRequested = true; feed(); worker.retry()
    }
    public func cancel() { isRequested = false; feed() }
    public func reset() {
        worker.reset(); source = ""; pieces = []; conversationID = nil
        isRequested = false; isGenerating = false; targetLanguage = "en"
    }

    public var translatedText: String? {
        guard isRequested, canTranslate else { return nil }
        var lines: [String] = []
        for piece in pieces {
            guard !piece.segments.isEmpty else { lines.append(piece.original); continue }
            guard piece.segments.allSatisfy({ worker.hasCompleted($0) }) else { return nil }
            let text = piece.segments.map { worker.text(for: $0) ?? $0.text }.joined(separator: " ")
            lines.append(piece.prefix + text + piece.suffix)
        }
        return lines.joined(separator: "\n")
    }
    public var problem: String? {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Generate or open a summary first." }
        if isGenerating { return "Wait for the summary to finish before translating it." }
        if OutputLanguage.option(targetLanguage) == nil { return "Choose an available translation language." }
        if source.count > 100_000 || pieces.reduce(0, { $0 + $1.segments.count }) > 512 {
            return "This summary is too long to translate at once. Generate a shorter summary and try again."
        }
        return nil
    }
    public var canTranslate: Bool { problem == nil }

    private func feed() {
        let active = isRequested && canTranslate
        var segments = active ? pieces.flatMap(\.segments) : []
        if active {
            // Use all prose to identify the summary language, rather than guessing independently
            // from short headings/names. Code is preserved verbatim and excluded from detection.
            let prose = String(segments.map(\.text).joined(separator: "\n").prefix(10_000))
            let hint = worker.translator?.sourceLanguage(for: prose, hint: nil)
            for index in segments.indices { segments[index].language = hint }
            // Keep the same attributed lines for completion checks and reconstruction.
            var cursor = 0
            pieces = pieces.map { piece in
                let end = cursor + piece.segments.count
                defer { cursor = end }
                return Piece(original: piece.original, prefix: piece.prefix, suffix: piece.suffix,
                             segments: Array(segments[cursor..<end]))
            }
        }
        worker.update(conversationID: "summary:" + (conversationID ?? ""), segments: segments,
                      fallbackLanguage: nil, options: .init(translateTranscript: active, translationTarget: targetLanguage))
    }

    private static func split(_ source: String) -> [Piece] {
        var fence: (character: Character, length: Int)?
        return source.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                let run = trimmed.prefix { $0 == marker.character }.count
                if run >= marker.length, trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
                return Piece(original: line, prefix: "", suffix: "", segments: [])
            }
            if let character = trimmed.first, character == "`" || character == "~" {
                let run = trimmed.prefix { $0 == character }.count
                if run >= 3, character != "`" || !trimmed.dropFirst(run).contains("`") {
                    fence = (character, run)
                    return Piece(original: line, prefix: "", suffix: "", segments: [])
                }
            }
            guard !trimmed.isEmpty else { return Piece(original: line, prefix: "", suffix: "", segments: []) }
            let marker = line.range(of: #"^\s*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+|>\s+)"#, options: .regularExpression)
            let prefix = marker.map { String(line[..<$0.upperBound]) }
                ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = String(line.dropFirst(prefix.count))
            let suffix = String(rest.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            var remaining = String(rest.dropLast(suffix.count))
            var segments: [TranscriptSegment] = []
            while !remaining.isEmpty {
                let head = remaining.prefix(8_000)
                let split = remaining.count > 8_000 ? head.lastIndex(where: \.isWhitespace) : nil
                let count = split.map { remaining.distance(from: remaining.startIndex, to: $0) } ?? head.count
                let part = String(remaining.prefix(max(1, count)))
                segments.append(.init(source: .you, text: part, isFinal: true, start: 0, end: 0))
                remaining = String(remaining.dropFirst(max(1, count))).trimmingCharacters(in: .whitespaces)
            }
            return Piece(original: line, prefix: prefix, suffix: suffix, segments: segments)
        }
    }
}
