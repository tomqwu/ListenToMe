import Foundation

/// The generated "Conversation — <date>" title and the rule for replacing it.
public enum ConversationTitle {
    public static let generatedPrefix = "Conversation — "
    /// The iPhone's default name for a conversation.
    public static let mobileDefault = "New conversation"
    /// An Apple Watch recording's conversation is named after its start until it is renamed.
    public static let watchPrefix = "Apple Watch · "
    /// A share-sheet import's conversation.
    public static let importedDefault = "Imported notes"

    public static func generated(_ formattedDate: String) -> String {
        generatedPrefix + formattedDate
    }

    /// True when the title is still the auto-generated one, so callers (e.g. Load from Calendar)
    /// may replace it. A user's own title — even an empty one they cleared — is never overwritten.
    public static func isGenerated(_ title: String) -> Bool {
        title.hasPrefix(generatedPrefix)
    }

    /// Any default name, on either platform (#221). An empty title is the user's, not a default.
    public static func isPlaceholder(_ title: String) -> Bool {
        isGenerated(title) || title.hasPrefix(watchPrefix) || title == mobileDefault || title == importedDefault
    }

    /// The style both platforms format the date of a generated title with.
    public static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    /// Exactly a title the app generated, for records saved before titles carried their origin.
    public static func isLegacyDefault(_ title: String, style: Date.FormatStyle = dateStyle) -> Bool {
        if title == mobileDefault { return true }
        for prefix in [watchPrefix, generatedPrefix] where title.hasPrefix(prefix) {
            return (try? Date(String(title.dropFirst(prefix.count)), strategy: style.parseStrategy)) != nil
        }
        return false
    }
}
