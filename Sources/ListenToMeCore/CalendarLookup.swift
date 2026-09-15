import Foundation

/// Result of asking the local calendar for the current or next meeting.
///
/// The old API returned `MeetingInfo?`, so "you denied Calendar access" and "you have no meeting
/// right now" were indistinguishable and shared one banner the user could neither dismiss nor act
/// on (issue #136).
public enum CalendarLookup: Sendable, Equatable {
    /// A meeting to pull context from.
    case meeting(MeetingInfo)
    /// Access is granted, but no suitable event is happening now or soon.
    case noMeeting
    /// The user denied (or has not granted) Calendar access.
    case denied
    /// EventKit itself failed; the description is carried for support.
    case failed(String)

    /// Banner text for a lookup that produced no meeting, or nil when one was found.
    public var message: String? {
        switch self {
        case .meeting: return nil
        case .noMeeting: return "No meeting is happening now or in the next few hours."
        case .denied: return "ListenToMe doesn't have Calendar access, so it can't find your meeting."
        case .failed(let reason): return "Couldn't read your calendar: \(reason)"
        }
    }

    /// True when the banner should offer a button that opens the Calendar privacy pane — only
    /// meaningful for a denial, which is the one case the user can fix in System Settings.
    public var offersPrivacySettings: Bool {
        if case .denied = self { return true }
        return false
    }
}

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
