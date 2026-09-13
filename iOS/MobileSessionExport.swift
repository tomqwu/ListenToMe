import Foundation
import ListenToMeCore

extension MobileSession {
    var readableShareText: String { Self.readableText(markdown) }

    static func readableShareText(for record: SessionRecord) -> String { readableText(markdown(for: record)) }

    static func readableText(_ markdown: String) -> String {
        MarkdownText.blocks(markdown).map { block in
            switch block {
            case .code(let code): return code
            case .markdown(let text):
                let styled = MarkdownText.inlineAttributed(text)
                return styled.runs.map { run in
                    let label = String(styled[run.range].characters)
                    if let link = run.link, label != link.absoluteString { return label + " (" + link.absoluteString + ")" }
                    return label
                }.joined()
            }
        }.joined(separator: "\n\n")
    }

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
