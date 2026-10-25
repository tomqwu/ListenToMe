import Foundation

/// Validated structured summary with verbatim evidence; the readable summary remains the fallback.
public struct SituationGrid: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public let text: String
        public let quotes: [String]
        public let owner: String?
        public let deadline: String?
    }
    public let summary: String
    public let open: [Item]
    public let todo: [Item]
    public let decided: [Item]

    public static let instructions = """
    Return only a JSON object with keys summary (string), open, todo, decided (arrays).
    Each array item has text (string), quotes (array of verbatim transcript excerpts), owner and deadline
    (null unless explicitly stated). Keep quotes in the original language. Every item needs evidence.
    Never invent an owner or deadline: when present, copy their exact words from a supporting quote.
    Open means unresolved questions; todo means explicit commitments; decided means explicit decisions.
    Preserve earlier items and their quotes from the previous meeting record across batches. Move or
    remove an item only when new evidence explicitly resolves or changes it. Do not treat suggestions
    as commitments or provisional speech as final decisions. Empty categories are empty arrays.
    The summary string is the readable narrative fallback and follows the requested response language.
    """

    public static func decode(_ output: String, segments: [TranscriptSegment]) -> SituationGrid? {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json\n"), text.hasSuffix("```") {
            text = String(text.dropFirst(8).dropLast(3))
        }
        guard text.utf8.count <= 128_000, let data = text.data(using: .utf8),
              let grid = try? JSONDecoder().decode(Self.self, from: data), grid.isValid(segments: segments) else { return nil }
        return grid
    }

    public func isValid(segments: [TranscriptSegment]) -> Bool {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, summary.count <= 16_000,
              open.count + todo.count + decided.count <= 100 else { return false }
        let finalized = segments.filter(\.isFinal)
        return (open + todo + decided).allSatisfy { item in
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.text.count <= 2000,
                  !item.quotes.isEmpty, item.quotes.count <= 8 else { return false }
            guard item.quotes.allSatisfy({ quote in
                quote.count >= 4 && quote.count <= 2000 && finalized.contains { $0.text.contains(quote) }
            }) else { return false }
            return [item.owner, item.deadline].compactMap { $0 }.allSatisfy { value in
                !value.isEmpty && item.quotes.contains { $0.contains(value) }
            }
        }
    }

    /// Literal text throughout: quotes and model text cannot create links or Markdown controls.
    public var markdown: String {
        func literal(_ text: String) -> String {
            text.reduce(into: "") { result, character in
                if "\\`*_{}[]<>()#+-.!|>".contains(character) { result.append("\\") }
                result.append(character)
            }
        }
        var blocks = [literal(summary)]
        for (heading, items) in [("Open", open), ("To-do", todo), ("Decided", decided)] {
            blocks.append("### " + heading)
            if items.isEmpty { blocks.append("None stated.") }
            for item in items {
                blocks.append("- " + literal(item.text))
                if let owner = item.owner { blocks.append("  Owner: " + literal(owner)) }
                if let deadline = item.deadline { blocks.append("  Deadline: " + literal(deadline)) }
                for quote in item.quotes { blocks.append("  Source: “" + literal(quote) + "”") }
            }
        }
        return blocks.joined(separator: "\n\n")
    }
}
