import Foundation

/// Prompt text built from the active vocabularies (issue #222). The text goes only to the AI
/// provider the user chose, inside the prompt that provider already receives.
public enum VocabularyPrompt {
    /// Characters of vocabulary guidance a provider with no prompt window (Ollama, cloud) receives.
    public static let guidanceCharacterLimit = 1_500
    /// Terms the correction prompt lists for one phrase.
    public static let correctionGlossaryLimit = 40

    /// The guidance budget for a provider: the full allowance with no window, otherwise a twentieth of
    /// the window (400 characters for Apple Intelligence's 8,000), so speech keeps the room.
    public static func characterLimit(forPromptWindow window: Int?) -> Int {
        guard let window else { return guidanceCharacterLimit }
        return min(guidanceCharacterLimit, max(0, window / 20))
    }

    /// Below this many characters (Apple Intelligence's 400) the guidance switches to its compact form:
    /// domain names instead of descriptions, short headings and glossary wording, and at least half of
    /// the space kept for the glossary itself, so My terms are never squeezed out by fixed text.
    public static let compactCharacterLimit = 800

    /// One block of session context: the active domains, a glossary, and (with `includeLayout`, which only
    /// summaries should pass) the domain's section headings. My terms come first, then preset terms that
    /// occur in `transcript`, then the presets' other terms in order, until `characterLimit` is reached.
    /// Nil when nothing is on or nothing fits.
    public static func guidance(for vocabulary: ActiveVocabulary, transcript: String? = nil,
                                characterLimit: Int = guidanceCharacterLimit, includeLayout: Bool = false) -> String? {
        guard !vocabulary.isEmpty, characterLimit > 0 else { return nil }
        let compact = characterLimit < compactCharacterLimit
        let domain: String? = vocabulary.domains.isEmpty ? nil : compact
            ? "Domain: " + vocabulary.domains.map(\.name).joined(separator: ", ") + "."
            : "Domain: " + vocabulary.domains.map { "\($0.name) — \($0.description)" }.joined(separator: " ")
        let layout = includeLayout ? layoutInstruction(for: vocabulary, compact: compact) : nil
        let prefix = compact ? "Expected terms (use these spellings if said; never add unsaid ones): "
            : "Glossary (the user's expected terms; use these spellings when one is clearly what was said, "
                + "and never add a term nobody said): "
        // The glossary is reserved its share first; the domain line and then the headings follow if they fit.
        let reserved = vocabulary.myTerms.isEmpty && vocabulary.domains.allSatisfy(\.terms.isEmpty) ? 0
            : characterLimit / 2
        var fixed = ""
        for piece in [domain, layout].compactMap({ $0 }) where fixed.count + piece.count + 1 <= characterLimit - reserved {
            fixed += (fixed.isEmpty ? "" : " ") + piece
        }
        let room = characterLimit - fixed.count - (fixed.isEmpty ? 0 : 1) - prefix.count - 1
        let glossary = glossaryTerms(for: vocabulary, transcript: transcript, characters: room)
        var result = fixed
        if !glossary.isEmpty { result += (result.isEmpty ? "" : " ") + prefix + glossary.joined(separator: ", ") + "." }
        return result.isEmpty ? nil : result
    }

    /// The summary headings sentence for the active domain, or nil when layouts are off or no preset is on.
    /// Only a Summary (the iOS Summary, the macOS Listener, and their automatic reviews) carries it.
    public static func layoutInstruction(for vocabulary: ActiveVocabulary, compact: Bool = false) -> String? {
        guard let layout = vocabulary.layoutDomain else { return nil }
        let headings = layout.summaryLayout.joined(separator: ", ")
        return compact ? "Summary headings: \(headings)."
            : "When writing a summary or meeting record, organize it under these headings: \(headings)."
    }

    /// Joins a preset persona and vocabulary guidance into the one "Context for this session" line the
    /// prompt builders already carry, so its cost is part of every measured prompt scaffold.
    public static func combined(persona: String?, guidance: String?) -> String? {
        let pieces = [persona, guidance].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }

    static func glossaryTerms(for vocabulary: ActiveVocabulary, transcript: String?, characters: Int) -> [String] {
        let spoken = transcript?.lowercased() ?? ""
        var seen = Set<String>()
        var ordered: [String] = []
        func take(_ terms: [String]) {
            for term in terms where seen.insert(term.lowercased()).inserted { ordered.append(term) }
        }
        take(vocabulary.myTerms)
        let presetTerms = interleaved(vocabulary.domains.map(\.terms))
        if !spoken.isEmpty { take(presetTerms.filter { spoken.contains($0.lowercased()) }) }
        take(presetTerms)
        var used = 0
        var result: [String] = []
        for term in ordered {
            let cost = term.count + (result.isEmpty ? 0 : 2)
            guard used + cost <= characters else { break }
            used += cost
            result.append(term)
        }
        return result
    }

    static func interleaved(_ lists: [[String]]) -> [String] {
        var result: [String] = []
        var index = 0
        while lists.contains(where: { index < $0.count }) {
            for list in lists where index < list.count { result.append(list[index]) }
            index += 1
        }
        return result
    }

    // MARK: - Transcript correction

    /// Added to the correction instructions when the request carries a glossary.
    public static let correctionInstruction = "The \"glossary\" field lists terms the user expects in this " +
        "conversation. When a word or phrase in the text sounds like or is a misspelling of a glossary term, " +
        "use the glossary spelling. Never insert a glossary term that was not spoken."

    /// The terms worth showing the correction model for one phrase: My terms, then preset terms, each
    /// ranked by how closely something in the phrase spells them, capped at `limit` (My terms take at
    /// most half). Builds a `CorrectionIndex` each call; a caller checking many phrases keeps one.
    public static func correctionGlossary(for vocabulary: ActiveVocabulary, text: String,
                                          limit: Int = correctionGlossaryLimit) -> [String] {
        CorrectionIndex(vocabulary).glossary(for: text, limit: limit)
    }

    /// The active vocabulary prepared for repeated correction lookups (issue #222 review): every term's
    /// spelling without spaces and its letter pairs are computed once, and a phrase is compared only
    /// with terms of a similar length that share enough letter pairs before any edit distance is run.
    public struct CorrectionIndex: Sendable, Equatable {
        struct Entry: Sendable, Equatable {
            let term: String
            let target: [Character]
            let span: Int
            let pairs: Set<String>
        }
        let mine: [Entry]
        let presets: [Entry]
        /// My terms need this resemblance; they are the user's own, so a looser match is worth showing.
        static let myTermThreshold = 0.5
        static let presetThreshold = 0.6

        public init(_ vocabulary: ActiveVocabulary) {
            var seen = Set<String>()
            func entries(_ terms: [String]) -> [Entry] {
                terms.compactMap { term in
                    let tokens = VocabularyText.tokens(term.lowercased())
                    let target = Array(tokens.joined())
                    guard target.count >= (VocabularyText.containsHan(term) ? 2 : 3),
                          seen.insert(term.lowercased()).inserted else { return nil }
                    return Entry(term: term, target: target, span: tokens.count, pairs: CorrectionIndex.pairs(target))
                }
            }
            mine = entries(vocabulary.myTerms)
            presets = entries(VocabularyPrompt.interleaved(vocabulary.domains.map(\.terms)))
        }

        public func glossary(for text: String, limit: Int = VocabularyPrompt.correctionGlossaryLimit) -> [String] {
            guard limit > 0, !(mine.isEmpty && presets.isEmpty) else { return [] }
            let entries = mine + presets
            let hanLengths = Set(entries.filter { VocabularyText.containsHan($0.term) }.flatMap {
                [max(2, $0.target.count - 1), $0.target.count, $0.target.count + 1]
            })
            let words = VocabularyText.tokens(text.lowercased())
            let windows = Window.all(in: words) + Window.han(in: words, lengths: hanLengths)
            func ranked(_ entries: [Entry], threshold: Double) -> [String] {
                entries.compactMap { entry -> (String, Double)? in
                    let score = Self.resemblance(entry, windows)
                    return score >= threshold ? (entry.term, score) : nil
                }.sorted { $0.1 > $1.1 }.map(\.0)
            }
            var result = Array(ranked(mine, threshold: Self.myTermThreshold).prefix(limit / 2))
            result += ranked(presets, threshold: Self.presetThreshold).prefix(limit - result.count)
            return result
        }

        struct Window {
            let text: [Character]
            let words: Int
            let pairs: Set<String>

            /// Sliding character windows let a Chinese term or near miss match inside a sentence.
            /// Lengths come from active terms only, keeping the work bounded by this small glossary.
            static func han(in words: [String], lengths: Set<Int>) -> [Window] {
                words.filter { VocabularyText.containsHan($0) }.flatMap { word -> [Window] in
                    let characters = Array(word)
                    return lengths.filter { $0 <= characters.count }.flatMap { length in
                        (0...(characters.count - length)).map { start in
                            let text = Array(characters[start..<(start + length)])
                            return Window(text: text, words: 1, pairs: CorrectionIndex.pairs(text))
                        }
                    }
                }
            }

            static func all(in words: [String]) -> [Window] {
                var result: [Window] = []
                for length in 1...(VocabularyCatalog.maximumTermWords + 1) where length <= words.count {
                    for start in 0...(words.count - length) {
                        let text = Array(words[start..<(start + length)].joined())
                        result.append(Window(text: text, words: length, pairs: CorrectionIndex.pairs(text)))
                    }
                }
                return result
            }
        }

        /// How closely the best run of words spells the term, from 0 to 1 (1 = identical).
        static func resemblance(_ entry: Entry, _ windows: [Window]) -> Double {
            var best = 0.0
            for window in windows where abs(window.words - entry.span) <= 1
                && abs(window.text.count - entry.target.count) <= max(2, entry.target.count / 2) {
                // Cheap filter first: too few shared letter pairs cannot reach the threshold.
                let shared = window.pairs.intersection(entry.pairs).count
                guard shared * 10 >= 3 * max(1, min(window.pairs.count, entry.pairs.count)) else { continue }
                let distance = VocabularyPrompt.editDistance(window.text, entry.target)
                best = max(best, 1 - Double(distance) / Double(max(window.text.count, entry.target.count)))
                if best == 1 { break }
            }
            return best
        }

        static func pairs(_ characters: [Character]) -> Set<String> {
            guard characters.count > 1 else { return [String(characters)] }
            return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
        }
    }

    static func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1))
            }
            previous = current
        }
        return previous[rhs.count]
    }
}

extension LLMRequest {
    /// The same request with vocabulary guidance appended to its system prompt, or unchanged when there
    /// is none. Used where a platform builds its own request instead of going through `PromptBuilder`.
    public func addingGuidance(_ guidance: String?) -> LLMRequest {
        guard let guidance, !guidance.isEmpty else { return self }
        return LLMRequest(system: system + "\nContext for this session: " + guidance, messages: messages,
                          purpose: purpose)
    }
}
