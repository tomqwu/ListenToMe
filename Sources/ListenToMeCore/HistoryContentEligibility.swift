import Foundation
import NaturalLanguage

/// Lexical content eligibility for optional semantic models. This does not load embedding assets.
/// Unavailable lexical tagging is unknown, not evidence that fallback OtherWord tags are nouns.
public enum HistoryContentEligibility {
    public enum Result: Sendable, Equatable { case eligible, insufficientContent, unknown }
    public enum Kind: Sendable { case passage, query }

    public static func evaluate(_ text: String, language: String? = nil, kind: Kind) -> Result {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .insufficientContent }
        let hint = language.flatMap(NaturalLanguageEmbedder.naturalLanguage)
        if kind == .query, hint == nil {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            let words = tokenizer.tokens(for: text.startIndex..<text.endIndex).filter { range in
                text[range].contains { $0.isLetter || $0.isNumber }
            }
            // A single word can be a noun in one language and a verb in another. A guessed
            // language/POS label cannot justify excluding it from compatible model queries.
            if words.count == 1 { return .unknown }
        }
        let selected: NLLanguage?
        if let hint { selected = hint } else {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            selected = recognizer.dominantLanguage
        }
        guard let selected,
              NLTagger.availableTagSchemes(for: .word, language: selected).contains(.lexicalClass) else { return .unknown }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(selected, range: text.startIndex..<text.endIndex)
        var count = 0
        var unknown = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            guard let tag else { unknown = true; return true }
            guard tag == .noun || tag == .otherWord else { return true }
            let word = text[range].lowercased()
            if selected == .english && NaturalLanguageEmbedder.genericNouns.contains(word) { return true }
            count += 1
            return true
        }
        guard !unknown else { return .unknown }
        // Same lexical classes, generic English exclusions and minima as NaturalLanguageEmbedder.
        // Vocabulary membership is still the selected embedding model's responsibility.
        let minimum = kind == .passage ? NaturalLanguageEmbedder.minimumPassageWords : 1
        return count >= minimum ? .eligible : .insufficientContent
    }
}
