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

    /// One block of session context: each active domain's description, a glossary, and (for summaries)
    /// the domain's section headings. My terms come first, then preset terms that occur in `transcript`,
    /// then the presets' other terms in order, until `characterLimit` is reached. Nil when nothing is on.
    public static func guidance(for vocabulary: ActiveVocabulary, transcript: String? = nil,
                                characterLimit: Int = guidanceCharacterLimit, includeLayout: Bool = true) -> String? {
        guard !vocabulary.isEmpty, characterLimit > 0 else { return nil }
        var parts: [String] = []
        if !vocabulary.domains.isEmpty {
            parts.append("Domain: " + vocabulary.domains.map { "\($0.name) — \($0.description)" }.joined(separator: " "))
        }
        if includeLayout, let layout = vocabulary.layoutDomain {
            parts.append("When writing a summary or meeting record, organize it under these headings: "
                + layout.summaryLayout.joined(separator: ", ") + ".")
        }
        let prefix = "Glossary (the user's expected terms; use these spellings when one is clearly what was said, "
            + "and never add a term nobody said): "
        var fixed = parts.joined(separator: " ")
        if fixed.count > characterLimit { fixed = String(fixed.prefix(characterLimit)) }
        let room = characterLimit - fixed.count - prefix.count - 2
        let glossary = glossaryTerms(for: vocabulary, transcript: transcript, characters: room)
        if !glossary.isEmpty { fixed += (fixed.isEmpty ? "" : " ") + prefix + glossary.joined(separator: ", ") + "." }
        return fixed.isEmpty ? nil : fixed
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
        func take(_ terms: [String]) { for term in terms where seen.insert(term.lowercased()).inserted { ordered.append(term) } }
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

    /// The terms worth showing the correction model for one phrase: My terms, then preset terms that
    /// look like something in the phrase (similar spelling once spaces are removed), capped at `limit`.
    public static func correctionGlossary(for vocabulary: ActiveVocabulary, text: String,
                                          limit: Int = correctionGlossaryLimit) -> [String] {
        guard !vocabulary.isEmpty, limit > 0 else { return [] }
        let words = VocabularyText.tokens(text.lowercased())
        var seen = Set<String>()
        var result: [String] = []
        for term in vocabulary.myTerms where result.count < limit / 2 && seen.insert(term.lowercased()).inserted {
            result.append(term)
        }
        let scored = interleaved(vocabulary.domains.map(\.terms)).compactMap { term -> (String, Double)? in
            guard !seen.contains(term.lowercased()) else { return nil }
            let score = resemblance(of: term, in: words)
            return score >= 0.6 ? (term, score) : nil
        }
        for (term, _) in scored.sorted(by: { $0.1 > $1.1 }) where result.count < limit && seen.insert(term.lowercased()).inserted {
            result.append(term)
        }
        return result
    }

    /// How closely the best run of words in `words` spells `term`, from 0 to 1 (1 = identical).
    static func resemblance(of term: String, in words: [String]) -> Double {
        let target = VocabularyText.tokens(term.lowercased()).joined()
        guard target.count >= 3, !words.isEmpty else { return 0 }
        let span = VocabularyText.tokens(term).count
        var best = 0.0
        for length in max(1, span - 1)...(span + 1) where length <= words.count {
            for start in 0...(words.count - length) {
                let candidate = words[start..<(start + length)].joined()
                guard abs(candidate.count - target.count) <= max(2, target.count / 2) else { continue }
                let distance = editDistance(Array(candidate), Array(target))
                best = max(best, 1 - Double(distance) / Double(max(candidate.count, target.count)))
            }
        }
        return best
    }

    /// Removes every glossary term from `text` (case-insensitively), so numbers that are part of a known
    /// term ("EC2", "ISO 9001") are not treated as numbers a correction must preserve.
    public static func removingTerms(_ terms: [String], from text: String) -> String {
        terms.sorted { $0.count > $1.count }.reduce(text) {
            $0.replacingOccurrences(of: $1, with: " ", options: [.caseInsensitive])
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
        return LLMRequest(system: system + "\nContext for this session: " + guidance, messages: messages, purpose: purpose)
    }
}
