import Foundation

/// The number-and-negation guard of AI transcript correction (issue #222 review). A correction may fix
/// how a word is spelled, never what was said: it must keep every number and every negation.
///
/// A glossary term may carry its own digits or negation ("EC2", "ISO 9001", "no-show rate", "without
/// prejudice"). Those are exempt only inside that term's own span, and only when the original already
/// held the same tokens in a span that spells like the term ("e c2" → "EC2"). So "show rate" →
/// "no-show rate" and "with prejudice" → "without prejudice" are refused (a negation appeared), and
/// "SOC 2 audit for 2 vendors" → "SOC 2 audit for vendors" is refused (a number outside the term went).
public enum CorrectionGuard {
    /// Conservatively, numerical expressions and common negation words. An extra guard, not proof that a
    /// model preserved meaning in every language.
    public static func protectedTerms(_ text: String) -> [String] {
        let normalized = normalize(text)
        return (regex?.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) ?? [])
            .compactMap { Range($0.range, in: normalized).map { String(normalized[$0]) } }
    }

    /// True when `corrected` keeps `original`'s numbers and negations, apart from those inside a glossary
    /// term that the original already said, with the same tokens, in a span spelled like the term.
    public static func preservesProtectedTerms(original: String, corrected: String, glossary: [String] = []) -> Bool {
        var remaining = normalize(corrected)
        var originalWords = normalize(original).words
        for term in glossary.map(normalize).sorted(by: { $0.count > $1.count }) {
            let tokens = protectedTerms(term)
            guard !tokens.isEmpty, let range = remaining.range(of: term),
                  let span = matchingSpan(of: term, tokens: tokens, in: originalWords) else { continue }
            remaining.replaceSubrange(range, with: " ")
            originalWords.removeSubrange(span)
        }
        return protectedTerms(remaining) == protectedTerms(originalWords.joined(separator: " "))
    }

    /// The run of original words this term corrects: spelled like it (resemblance ≥ 0.6 once spaces and
    /// punctuation are removed) and carrying exactly the term's numbers and negations.
    static func matchingSpan(of term: String, tokens: [String], in words: [String]) -> Range<Int>? {
        let target = VocabularyText.tokens(term).joined()
        let span = max(1, term.words.count)
        var best: (range: Range<Int>, score: Double)?
        for length in max(1, span - 1)...(span + 1) where length <= words.count {
            for start in 0...(words.count - length) {
                let window = Array(words[start..<(start + length)])
                guard protectedTerms(window.joined(separator: " ")) == tokens else { continue }
                let candidate = VocabularyText.tokens(window.joined(separator: " ")).joined()
                let longest = max(candidate.count, target.count, 1)
                let score = 1 - Double(VocabularyPrompt.editDistance(Array(candidate), Array(target))) / Double(longest)
                if score >= 0.6, score > (best?.score ?? 0) { best = (start..<(start + length), score) }
            }
        }
        return best?.range
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    private static let regex = try? NSRegularExpression(pattern:
        #"\d+(?:[.,:/-]\d+)*|\b(?:not|no|never|cannot|can't|don't|doesn't|didn't|won't|isn't|wasn't|without)\b|不|没|無|未"#)
}

private extension String {
    var words: [String] {
        split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
