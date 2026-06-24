import Foundation

/// Formats a meeting session into a shareable Markdown document. Pure (no I/O, no clock) so it is
/// fully unit-testable; the caller supplies the title/timestamp and the file write happens in the
/// app layer.
public enum SessionExporter {
    /// Builds a Markdown document from the session's transcript and AI-pane outputs. Empty optional
    /// sections (notes, summary, suggestions) are omitted; the transcript section is always present.
    public static func markdown(
        title: String,
        transcript: [TranscriptSegment],
        notes: String = "",
        listenerSummary: String = "",
        quickSuggestion: String = "",
        deepAnswer: String = ""
    ) -> String {
        var out = "# \(title)\n"

        func section(_ heading: String, _ body: String) {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out += "\n## \(heading)\n\n\(trimmed)\n"
        }

        section("Context notes", notes)

        let lines = transcript.map { seg in
            "- **\(seg.source == .you ? "You" : "Others"):** \(seg.text)"
        }
        let transcriptBody = lines.isEmpty ? "_(no transcript captured)_" : lines.joined(separator: "\n")
        out += "\n## Transcript\n\n\(transcriptBody)\n"

        section("Listener summary", listenerSummary)
        section("Quick suggestion", quickSuggestion)
        section("Deep answer", deepAnswer)
        return out
    }
}
