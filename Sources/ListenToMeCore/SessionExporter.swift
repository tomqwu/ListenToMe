import Foundation

/// The file formats a conversation can be exported in (issue #130). See `docs/export-formats.md`.
public enum SessionExportFormat: String, CaseIterable, Sendable, Identifiable {
    case markdown, plainText, srt, webVTT, json

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        case .srt: return "srt"
        case .webVTT: return "vtt"
        case .json: return "json"
        }
    }

    /// The menu title, e.g. "Subtitles (SRT)".
    public var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .plainText: return "Plain text"
        case .srt: return "Subtitles (SRT)"
        case .webVTT: return "Subtitles (WebVTT)"
        case .json: return "JSON"
        }
    }

    /// Subtitles are made of timed cues, so they need a conversation whose lines carry times.
    public var needsTimestamps: Bool { self == .srt || self == .webVTT }
}

/// Formats a conversation for export. Pure (no I/O, no clock) so every format is golden-file tested;
/// the caller supplies the record and time zone, and the file write happens in the app layer.
///
/// Timestamps appear only where the transcription engine reported them (`TranscriptTimestamp`), and
/// the language is the one the conversation was recorded in (`SessionRecord.language`, issue #206).
public enum SessionExporter {
    /// The text of `record` in `format`. `timestamps` applies to Markdown and plain text; subtitles
    /// always use the times and JSON always carries them.
    public static func export(_ record: SessionRecord, as format: SessionExportFormat, timestamps: Bool = true,
                              timeZone: TimeZone = .current) -> String {
        switch format {
        case .markdown: return markdown(for: record, timestamps: timestamps, timeZone: timeZone)
        case .plainText: return plainText(for: record, timestamps: timestamps, timeZone: timeZone)
        case .srt: return srt(for: record)
        case .webVTT: return webVTT(for: record)
        case .json: return json(for: record)
        }
    }

    /// The formats `record` can be exported in: subtitles only when its lines carry times.
    public static func formats(for record: SessionRecord) -> [SessionExportFormat] {
        let timed = TranscriptTimestamp.hasTimes(record.segments ?? [])
        return SessionExportFormat.allCases.filter { timed || !$0.needsTimestamps }
    }

    /// Builds a Markdown document from the session's transcript and AI-pane outputs. Empty optional
    /// sections (notes, summary, suggestions) are omitted; the transcript section is always present.
    public static func markdown(
        title: String,
        transcript: [TranscriptSegment],
        notes: String = "",
        listenerSummary: String = "",
        quickSuggestion: String = "",
        deepAnswer: String = "",
        timestamps: Bool = true
    ) -> String {
        markdown(title: title, header: nil, transcript: transcript, legacyTranscript: nil, notes: notes,
                 listenerSummary: listenerSummary, quickSuggestion: quickSuggestion, deepAnswer: deepAnswer,
                 attachments: [], timestamps: timestamps)
    }

    /// The full Markdown document for a saved or open conversation: title, date and language, the
    /// transcript, speech corrections, the AI outputs and attachment names. A record saved before
    /// segments were kept exports its flattened transcript as it was saved.
    public static func markdown(for record: SessionRecord, timestamps: Bool = true,
                                timeZone: TimeZone = .current) -> String {
        markdown(title: record.title, header: header(record, timeZone: timeZone), transcript: record.segments ?? [],
                 legacyTranscript: record.segments == nil ? record.transcript : nil, notes: record.notes ?? "",
                 listenerSummary: record.summary, quickSuggestion: record.quickSuggestion ?? "",
                 deepAnswer: record.deepAnswer ?? "", attachments: (record.attachments ?? []).map(\.name),
                 timestamps: timestamps, selectionSummaries: record.selectionSummaries ?? [])
    }

    // swiftlint:disable:next function_parameter_count
    private static func markdown(title: String, header: String?, transcript: [TranscriptSegment],
                                 legacyTranscript: String?, notes: String, listenerSummary: String,
                                 quickSuggestion: String, deepAnswer: String, attachments: [String],
                                 timestamps: Bool, selectionSummaries: [SelectionSummary] = []) -> String {
        var out = "# \(title)\n"
        if let header { out += "\n_\(header)_\n" }

        func section(_ heading: String, _ body: String) {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out += "\n## \(heading)\n\n\(trimmed)\n"
        }

        section("Context notes", notes)

        let lines = transcript.map { seg in
            "- \(stamp(seg, timestamps))**\(seg.speakerLabel):** \(seg.text)"
        }
        let legacy = legacyTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let transcriptBody = !lines.isEmpty ? lines.joined(separator: "\n")
            : legacy.isEmpty ? "_(no transcript captured)_" : legacy
        out += "\n## Transcript\n\n\(transcriptBody)\n"
        let corrections = transcript.compactMap { segment -> String? in
            guard let original = segment.originalText else { return nil }
            return "- Original: \(original)\n  AI correction: \(segment.text)"
        }
        section("Speech corrections (original wording)", corrections.joined(separator: "\n"))

        section("Listener summary", listenerSummary)
        section("Quick suggestion", quickSuggestion)
        section("Deep answer", deepAnswer)
        section("Selection summaries", SelectionSummary.markdown(selectionSummaries) ?? "")
        section("Attachments", attachments.map { "- \($0)" }.joined(separator: "\n"))
        return out
    }

    /// The conversation as plain text: a title line, the date and language, the summaries and notes,
    /// then one `[mm:ss] Speaker: text` line per transcript line.
    public static func plainText(for record: SessionRecord, timestamps: Bool = true,
                                 timeZone: TimeZone = .current) -> String {
        var out = MarkdownVault.singleLine(record.title) + "\n" + header(record, timeZone: timeZone) + "\n"
        func section(_ heading: String, _ body: String?) {
            let trimmed = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out += "\n\(heading)\n\(trimmed)\n"
        }
        section("Summary", record.summary)
        section("Quick summary", record.quickSuggestion)
        section("Deep summary", record.deepAnswer)
        section("Notes", record.notes)
        let transcript: String
        if let segments = record.segments {
            transcript = segments.compactMap { segment -> String? in
                let text = MarkdownVault.singleLine(segment.text)
                guard !text.isEmpty else { return nil }
                return stamp(segment, timestamps) + MarkdownVault.singleLine(segment.speakerLabel) + ": " + text
            }.joined(separator: "\n")
        } else {
            transcript = record.transcript
        }
        section("Transcript", transcript.isEmpty ? "(no transcript captured)" : transcript)
        section("Attachments", (record.attachments ?? []).map { MarkdownVault.singleLine($0.name) }
            .joined(separator: "\n"))
        return out
    }

    /// A concise shareable recap: title, the listener summary, and any Quick/Deep notes — WITHOUT
    /// the full transcript. Omits empty sections; returns the title alone if nothing else is present.
    public static func recap(
        title: String,
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
        section("Summary", listenerSummary)
        section("Quick suggestion", quickSuggestion)
        section("Deep answer", deepAnswer)
        return out
    }

    /// The recap of a saved conversation.
    public static func recap(for record: SessionRecord) -> String {
        recap(title: record.title, listenerSummary: record.summary,
              quickSuggestion: record.quickSuggestion ?? "", deepAnswer: record.deepAnswer ?? "")
    }

    /// `Recorded 2026-10-23 14:35 · Language: en-US`; the language part only when it is known.
    static func header(_ record: SessionRecord, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.date)
        var out = String(format: "Recorded %04d-%02d-%02d %02d:%02d", parts.year ?? 0, parts.month ?? 0,
                         parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        let languages = record.conversationLanguages.all
        if languages.count == 1 {
            out += " · Language: \(languages[0])"
        } else if !languages.isEmpty {
            out += " · Languages: " + languages.joined(separator: ", ")
        }
        return out
    }

    /// `[01:05] ` for a line its engine timed, else nothing.
    private static func stamp(_ segment: TranscriptSegment, _ timestamps: Bool) -> String {
        timestamps && TranscriptTimestamp.isTimed(segment) ? "[\(TranscriptTimestamp.clock(segment.start))] " : ""
    }
}
