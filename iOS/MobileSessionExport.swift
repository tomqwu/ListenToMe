import Foundation
import ListenToMeCore

extension MobileSession {
    /// Export the chosen saved record without opening it or changing the active conversation.
    static func markdown(for record: SessionRecord) -> String {
        var text = SessionExporter.markdown(title: record.title, transcript: record.segments ?? [],
                                            notes: record.notes ?? "", listenerSummary: record.summary,
                                            quickSuggestion: record.quickSuggestion ?? "", deepAnswer: record.deepAnswer ?? "")
        if record.segments == nil && !record.transcript.isEmpty {
            text = text.replacingOccurrences(of: "## Transcript\n\n_(no transcript captured)_",
                                            with: "## Transcript\n\n" + record.transcript)
        }
        if let attachments = record.attachments, !attachments.isEmpty {
            text += "\n## Attachments\n" + attachments.map { "- \($0.name)" }.joined(separator: "\n")
        }
        return text
    }
}
