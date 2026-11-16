import Foundation

/// One thing Share can send from a conversation: either summary on its own, the whole conversation,
/// or its saved audio files.
public enum ConversationShareContent: String, CaseIterable, Identifiable, Sendable {
    case quickSummary, fullSummary, conversation, audio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quickSummary: return "Quick summary"
        case .fullSummary: return "Full summary"
        case .conversation: return "Whole conversation"
        case .audio: return "Audio"
        }
    }
}

/// What Share offers for a conversation and the text each choice sends. A summary is shared with only
/// the title and date, never the transcript; choices with nothing to send are not offered.
public enum ConversationShare {
    public static func contents(for record: SessionRecord, hasAudio: Bool) -> [ConversationShareContent] {
        ConversationShareContent.allCases.filter { content in
            switch content {
            case .quickSummary: return !trimmed(record.quickSuggestion).isEmpty
            case .fullSummary: return !trimmed(record.summary).isEmpty
            case .conversation: return hasConversation(record)
            case .audio: return hasAudio
            }
        }
    }

    /// The text to share, or nil for audio (which shares files) and for a choice with nothing in it.
    public static func text(_ content: ConversationShareContent, for record: SessionRecord,
                            timeZone: TimeZone = .current) -> String? {
        switch content {
        case .quickSummary: return summary(content.title, record.quickSuggestion, record, timeZone)
        case .fullSummary: return summary(content.title, record.summary, record, timeZone)
        case .conversation:
            return hasConversation(record) ? SessionExporter.plainText(for: record, timeZone: timeZone) : nil
        case .audio: return nil
        }
    }

    private static func summary(_ heading: String, _ body: String?, _ record: SessionRecord,
                                _ timeZone: TimeZone) -> String? {
        let body = trimmed(body)
        guard !body.isEmpty else { return nil }
        return MarkdownVault.singleLine(record.title) + "\n" + SessionExporter.header(record, timeZone: timeZone)
            + "\n\n" + heading + "\n" + body + "\n"
    }

    private static func hasConversation(_ record: SessionRecord) -> Bool {
        if let segments = record.segments, segments.contains(where: { !trimmed($0.text).isEmpty }) { return true }
        return !trimmed(record.transcript).isEmpty || !trimmed(record.summary).isEmpty
            || !trimmed(record.quickSuggestion).isEmpty || !trimmed(record.notes).isEmpty
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
