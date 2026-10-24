import Foundation

/// The JSON export (issue #130): a documented, versioned schema (`docs/export-formats.md`) rather than
/// the app's internal archive file, so tools can rely on it while the archive keeps evolving.
extension SessionExporter {
    /// Identifies the document; bump `jsonSchemaVersion` on any change that is not purely additive.
    public static let jsonSchemaName = "listentome.conversation"
    public static let jsonSchemaVersion = 1

    /// The conversation as JSON (UTF-8, pretty-printed, keys sorted so the output is stable).
    public static func json(for record: SessionRecord) -> String {
        let segments = record.segments ?? []
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.formatOptions = [.withInternetDateTime]
        func millis(_ value: TimeInterval) -> Double { (value * 1000).rounded() / 1000 }

        var seen = Set<String>()
        let speakers = segments.compactMap { segment -> SessionExportJSON.Speaker? in
            let name = MarkdownVault.singleLine(segment.speakerLabel)
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(name).inserted else { return nil }
            return SessionExportJSON.Speaker(name: name, id: segment.speakerID, source: segment.source.rawValue)
        }
        let lines = segments.map { segment in
            let timed = TranscriptTimestamp.isTimed(segment)
            return SessionExportJSON.Segment(speaker: MarkdownVault.singleLine(segment.speakerLabel),
                                             speakerID: segment.speakerID, source: segment.source.rawValue,
                                             text: segment.text, start: timed ? millis(segment.start) : nil,
                                             end: timed ? millis(max(segment.start, segment.end)) : nil,
                                             originalText: segment.originalText,
                                             language: segment.language.flatMap(ConversationLanguages.normalized))
        }
        let languages = record.conversationLanguages
        let document = SessionExportJSON(
            schema: jsonSchemaName, version: jsonSchemaVersion, id: record.id, title: record.title,
            date: dateFormatter.string(from: record.date), language: languages.current, languages: languages.all,
            hasTimestamps: TranscriptTimestamp.hasTimes(segments),
            duration: TranscriptTimestamp.duration(of: segments).map(millis), speakers: speakers,
            summary: record.summary, quickSummary: record.quickSuggestion ?? "", deepSummary: record.deepAnswer ?? "",
            notes: record.notes ?? "", segments: lines,
            transcript: record.segments == nil ? record.transcript : nil,
            attachments: (record.attachments ?? []).map { SessionExportJSON.Attachment(name: $0.name) },
            selectionSummaries: (record.selectionSummaries ?? []).map {
                SessionExportJSON.SelectionSummary(date: dateFormatter.string(from: $0.date), start: millis($0.start),
                                                   end: millis($0.end), lineCount: $0.lineCount,
                                                   shortened: $0.shortened, text: $0.text)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Every field is a string, number, bool or array of them: encoding cannot fail.
        let data = (try? encoder.encode(document)) ?? Data()
        return (String(bytes: data, encoding: .utf8) ?? "") + "\n"
    }
}

/// Version 1 of the JSON export. Optional segment and speaker fields are left out when unknown; the
/// top-level `language` and `duration` are `null` instead, so every document has the same keys.
struct SessionExportJSON: Encodable {
    struct Speaker: Encodable {
        let name: String
        let id: String?
        let source: String
    }
    struct Segment: Encodable {
        let speaker: String
        let speakerID: String?
        let source: String
        let text: String
        let start: Double?
        let end: Double?
        let originalText: String?
        /// The language this line was recognized in, when the app kept it (#206).
        let language: String?
    }
    struct Attachment: Encodable { let name: String }
    /// A saved summary of selected lines (#234); times in seconds on the conversation's timeline.
    struct SelectionSummary: Encodable {
        let date: String
        let start: Double
        let end: Double
        let lineCount: Int
        let shortened: Bool
        let text: String
    }

    let schema: String
    let version: Int
    let id: String
    let title: String
    let date: String
    let language: String?
    let languages: [String]
    let hasTimestamps: Bool
    let duration: Double?
    let speakers: [Speaker]
    let summary: String
    let quickSummary: String
    let deepSummary: String
    let notes: String
    let segments: [Segment]
    /// Only for conversations saved before lines were kept one by one.
    let transcript: String?
    let attachments: [Attachment]
    let selectionSummaries: [SelectionSummary]

    enum CodingKeys: String, CodingKey {
        case schema, version, id, title, date, language, languages, hasTimestamps, duration, speakers
        case summary, quickSummary, deepSummary, notes, segments, transcript, attachments, selectionSummaries
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encode(language, forKey: .language)   // null when unknown, never missing
        try container.encode(languages, forKey: .languages)
        try container.encode(hasTimestamps, forKey: .hasTimestamps)
        try container.encode(duration, forKey: .duration)
        try container.encode(speakers, forKey: .speakers)
        try container.encode(summary, forKey: .summary)
        try container.encode(quickSummary, forKey: .quickSummary)
        try container.encode(deepSummary, forKey: .deepSummary)
        try container.encode(notes, forKey: .notes)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(transcript, forKey: .transcript)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(selectionSummaries, forKey: .selectionSummaries)
    }
}
