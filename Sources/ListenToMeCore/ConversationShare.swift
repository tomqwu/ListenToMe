import Foundation

/// One thing Share can send from a conversation: a summary on its own, or its saved audio files.
/// Share never sends the transcript or notes; Export as is the explicit way to export those.
public enum ConversationShareContent: String, CaseIterable, Identifiable, Sendable {
    case fullSummary, quickSummary, audio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fullSummary: return "Full summary"
        case .quickSummary: return "Quick summary"
        case .audio: return "Audio"
        }
    }
}

/// What Share offers for a conversation and the text each choice sends. A summary is shared with only
/// the title and date; choices with nothing to send are not offered.
public enum ConversationShare {
    /// What a plain Share sends: the full summary, else the Quick summary. Never the transcript.
    public static func defaultContent(for record: SessionRecord) -> ConversationShareContent? {
        contents(for: record, hasAudio: false).first
    }

    public static func contents(for record: SessionRecord, hasAudio: Bool) -> [ConversationShareContent] {
        ConversationShareContent.allCases.filter { content in
            switch content {
            case .fullSummary: return !trimmed(record.summary).isEmpty
            case .quickSummary: return !trimmed(record.quickSuggestion).isEmpty
            case .audio: return hasAudio
            }
        }
    }

    /// The text to share, or nil for audio (which shares files) and for a summary that is empty.
    public static func text(_ content: ConversationShareContent, for record: SessionRecord,
                            timeZone: TimeZone = .current) -> String? {
        switch content {
        case .fullSummary: return summary(content.title, record.summary, record, timeZone)
        case .quickSummary: return summary(content.title, record.quickSuggestion, record, timeZone)
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

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
