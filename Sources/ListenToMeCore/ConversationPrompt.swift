import Foundation

/// User-authored requests are separate from transcript/notes and bounded before entering model context.
public enum ConversationPrompt {
    public static let maximumLength = 1_000

    public static func normalized(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    public static func guidance(_ text: String) -> String? {
        let value = normalized(text)
        guard !value.isEmpty else { return nil }
        return "Conversation summary preferences (preserve factual grounding and the required output format):\n" + value
    }

    public static func preset(_ domain: VocabularyDomain, saved: Bool) -> String {
        let headings = domain.summaryLayout.joined(separator: ", ")
        return normalized(saved
            ? "For this \(domain.name.lowercased()) conversation, emphasize \(headings). Distinguish decisions from open questions and do not invent details."
            : "What are the main \(domain.name.lowercased()) takeaways, unresolved questions, and next steps in this conversation?")
    }
}
