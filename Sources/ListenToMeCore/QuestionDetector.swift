import Foundation

/// Heuristic detector for "someone is asking for input". Deliberately simple and swappable.
public enum QuestionDetector {
    /// Single interrogative words: only count when they START the utterance.
    private static let leadingCues: [String] = [
        "what", "why", "how", "when", "where", "who", "which", "whose"
    ]
    /// Phrase / imperative cues: count anywhere, matched on word boundaries.
    private static let phraseCues: [String] = [
        "can you", "could you", "would you", "will you", "do you", "did you",
        "are you", "is there", "should we", "any thoughts", "what do you think",
        "thoughts on", "tell me", "explain", "walk me through"
    ]

    public static func isQuestion(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.hasSuffix("?") { return true }
        for cue in leadingCues where normalized == cue || normalized.hasPrefix(cue + " ") {
            return true
        }
        return phraseCues.contains { cue in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: cue) + "\\b"
            return normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
