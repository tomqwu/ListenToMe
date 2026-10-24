import Foundation

/// The context-aware "Suggested" prompt chips (#61): two or three literal, one-tap requests drawn from
/// the live conversation, shown above the fixed Quick actions.
///
/// Suggestions never cost a model call of their own. They ride on passes that already run — the Quick
/// evaluator's JSON decision (`QuickSummaryDecision.suggestions`) while Auto is on, and the user's own
/// manual Quick Summary — so with Auto off, AI off, or no pass the user triggered, no chip is produced.
/// A tap sends the literal text through the normal Quick or Deep path; nothing is ever sent by itself.
///
/// This value only validates, rate-limits and remembers chips. It is pure and clock-injected, so the
/// parsing, cadence and clearing rules are unit-tested without a model.
public struct SuggestedPrompts: Equatable, Sendable {
    /// At most this many chips are shown.
    public static let maximumCount = 3
    /// A chip longer than this is rejected, never truncated: a cut-off literal prompt is not a prompt.
    public static let maximumLength = 60
    /// Chips already on screen are replaced at most this often by automatic passes, so a chip never
    /// changes under the pointer on every five-second Quick read. A newer set that arrives sooner is
    /// held and shown on the first pass after the window, even when that pass brings nothing new.
    public static let minimumRefreshInterval: TimeInterval = 20

    /// The chips to show, in the model's order.
    public private(set) var prompts: [String] = []
    /// The newest valid set held back by `minimumRefreshInterval`.
    private var pending: [String]?
    private var shownAt: TimeInterval?
    /// Normalized keys of chips the user already tapped in this conversation; never suggested again.
    private var used: Set<String> = []

    public init() {}

    public var isEmpty: Bool { prompts.isEmpty }

    /// Offers the suggestions of one completed model pass.
    ///
    /// - Parameters:
    ///   - candidates: raw model output; junk, duplicates and over-long entries are dropped.
    ///   - now: seconds on the caller's clock.
    ///   - force: true for a pass the user explicitly asked for (a manual Quick Summary), which
    ///     replaces the chips at once instead of waiting out the refresh window.
    /// - Returns: true when the visible chips changed.
    @discardableResult
    public mutating func offer(_ candidates: [String], at now: TimeInterval, force: Bool = false) -> Bool {
        let fresh = Self.sanitize(candidates, excluding: used)
        if !fresh.isEmpty { pending = fresh }
        // An empty or junk-only pass keeps the chips that are showing: they are still grounded in
        // this conversation, and a keep decision carries no suggestions by design.
        guard let next = pending else { return false }
        if !force, !prompts.isEmpty, let shownAt, now - shownAt < Self.minimumRefreshInterval { return false }
        pending = nil
        guard next != prompts else { return false }
        prompts = next
        shownAt = now
        return true
    }

    /// The user tapped `prompt`: it leaves the row and is not suggested again in this conversation.
    public mutating func use(_ prompt: String) {
        let key = Self.key(prompt)
        used.insert(key)
        prompts.removeAll { Self.key($0) == key }
        pending = pending?.filter { Self.key($0) != key }
    }

    /// Removes every chip — on a provider change or when AI is turned off — while still remembering
    /// which chips were already used in this conversation.
    public mutating func clear() {
        prompts = []
        pending = nil
        shownAt = nil
    }

    // MARK: - Validation

    /// Cleans, validates and de-duplicates candidates, keeping at most `maximumCount`.
    public static func sanitize(_ candidates: [String], excluding excluded: Set<String> = []) -> [String] {
        var seen = excluded
        var result: [String] = []
        for candidate in candidates {
            guard result.count < maximumCount, let prompt = clean(candidate) else { continue }
            guard seen.insert(key(prompt)).inserted else { continue }
            result.append(prompt)
        }
        return result
    }

    /// One candidate as a chip, or nil when it is not a usable literal prompt.
    public static func clean(_ candidate: String) -> String? {
        // A chip is one line. A newline means the model wrote a paragraph or several items in one.
        guard !candidate.contains(where: \.isNewline) else { return nil }
        var text = candidate.trimmingCharacters(in: .whitespaces)
        // Unwrap first, or "**Ask about Q3**" would lose its leading "*" as a list marker.
        text = strippedMarker(unwrappedEmphasis(text))
        // Quotes around the request are decoration, not part of it. So is emphasis wrapping the whole
        // request ("**Ask about Q3**"); markup inside it ("Explain __init__") is left alone.
        let quotes = CharacterSet(charactersIn: "\"“”‘’«»")
        text = unwrappedEmphasis(text.trimmingCharacters(in: quotes.union(.whitespaces)))
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty, text.count <= maximumLength,
              text.filter(\.isLetter).count >= 3 else { return nil }
        // Markup, JSON, fences, links and placeholders are model debris, never a request to send.
        let lowered = text.lowercased()
        guard !text.contains(where: { "{}[]<>|\\".contains($0) }),
              !lowered.contains("http://"), !lowered.contains("https://"), !lowered.contains("www."),
              !lowered.hasPrefix("no suggestion"), !lowered.hasPrefix("suggested:"),
              !placeholders.contains(key(text)) else { return nil }
        return text
    }

    static let placeholders: Set<String> = [
        "none", "n/a", "na", "null", "nil", "nothing", "no", "empty", "prompt", "request", "suggestion",
        "suggestions", "question", "your prompt", "your question",
    ]

    /// The comparison key: case-, diacritic- and width-insensitive, ignoring spacing and trailing
    /// punctuation, so "Ask about pricing?" and "ask about pricing" are one chip.
    public static func key(_ prompt: String) -> String {
        prompt.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// `text` without one pair of emphasis markers that wraps all of it.
    private static func unwrappedEmphasis(_ text: String) -> String {
        for marker in ["**", "__", "*", "_", "`"] where text.count > marker.count * 2
            && text.hasPrefix(marker) && text.hasSuffix(marker) {
            return String(text.dropFirst(marker.count).dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// The text without a leading "-", "*", "•", ">" or "1." / "1)" list marker.
    private static func strippedMarker(_ line: String) -> String {
        var rest = Substring(line)
        if let marker = rest.first, "-*•>".contains(marker) {
            rest = rest.drop { "-*•> ".contains($0) }
        } else {
            let digits = rest.prefix(while: \.isNumber)
            if !digits.isEmpty, digits.count <= 2, let separator = rest.dropFirst(digits.count).first,
               ".)".contains(separator) {
                rest = rest.dropFirst(digits.count + 1)
            }
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - On-device prose

    /// The clause the prose (Apple Intelligence) Quick prompt appends. The on-device model has a small
    /// window and cannot be held to the JSON envelope, so it is asked for one marked trailing block
    /// that `splitProse` reads strictly; anything else means no chips. The heading stays in English
    /// in every conversation language, so one parser serves them all.
    public static let proseInstructions = """
    Then, only if something substantive was said, end with a line "Suggested:" (always this English \
    word, whatever the language) and up to three short requests the user could ask next about this \
    conversation, one per line starting with "> ", each at most 60 characters. Write nothing after them.
    """

    /// Splits a prose Quick answer into the recap text and its suggested prompts.
    ///
    /// Strict by design, so a suggestion block can never take a real takeaway:
    /// - the block must be the answer's final section: exactly one "Suggested:" heading (a few English
    ///   variants, bold or heading markers allowed), followed only by `> ` lines up to the end (blank
    ///   lines and a closing code fence after the block are ignored);
    /// - `>` is the only suggestion marker: `-`, `*`, `•` and numbered lines are bullets, never chips;
    /// - a heading anywhere else, a second heading, or any blank or other line inside the block means
    ///   no chips, and the whole answer stays the recap;
    /// - a block with no recap above it, or after "No key takeaway yet.", gives no chips.
    public static func splitProse(_ response: String) -> (body: String, suggestions: [String]) {
        var lines = response.components(separatedBy: .newlines)
        while let last = lines.last?.trimmingCharacters(in: .whitespaces), last.isEmpty || last == "```" {
            lines.removeLast()
        }
        let headings = lines.indices.filter { isSuggestionHeading(lines[$0]) }
        guard headings.count == 1, let heading = headings.first else { return (response, []) }
        let block = lines[(heading + 1)...].map { $0.trimmingCharacters(in: .whitespaces) }
        guard !block.isEmpty, block.allSatisfy({ $0.hasPrefix(">") }) else { return (response, []) }
        let body = lines[..<heading].joined(separator: "\n")
        let recap = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recap.isEmpty, !recap.lowercased().hasPrefix("no key takeaway") else { return (body, []) }
        return (body, sanitize(block))
    }

    private static func isSuggestionHeading(_ line: String) -> Bool {
        let bare = line.trimmingCharacters(in: CharacterSet(charactersIn: "*#_ \t")).lowercased()
        return ["suggested:", "suggestions:", "suggested prompts:", "suggested questions:"].contains(bare)
    }
}
