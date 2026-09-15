import Foundation

/// The generated "Conversation — <date>" title and the rule for replacing it.
public enum ConversationTitle {
    public static let generatedPrefix = "Conversation — "

    public static func generated(_ formattedDate: String) -> String {
        generatedPrefix + formattedDate
    }

    /// True when the title is still the auto-generated one, so callers (e.g. Load from Calendar)
    /// may replace it. A user's own title — even an empty one they cleared — is never overwritten.
    public static func isGenerated(_ title: String) -> Bool {
        title.hasPrefix(generatedPrefix)
    }
}
