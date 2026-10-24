import Foundation

/// The transcription languages a conversation was actually recorded in (issue #206), kept on its
/// `SessionRecord` so Save to folder and exports describe the conversation itself rather than whatever
/// the language setting says today.
///
/// `current` is the language its latest recording is transcribed in, including an Automatic switch
/// (#197/#199) and an Undo; `all` lists every language its lines are in, in order of first use.
/// Identifiers are stored as BCP-47 tags (`en-US`), so `en_US` and `en-US` are the same language.
public struct ConversationLanguages: Sendable, Equatable {
    public private(set) var current: String?
    public private(set) var all: [String]

    public init(current: String? = nil, all: [String] = []) {
        self.current = current.flatMap(Self.normalized)
        var seen: [String] = []
        for identifier in all.compactMap(Self.normalized) + [self.current].compactMap({ $0 })
        where !seen.contains(identifier) {
            seen.append(identifier)
        }
        self.all = seen
    }

    public var isEmpty: Bool { all.isEmpty }

    /// A recording, the part after a switch, or the language an Undo switched back to, is transcribed
    /// in `identifier`. Nothing is ever removed here: what leaves `all` is decided by the lines
    /// (`resolving(recorded:segments:)`), so an Undo cannot drop a language that lines are still in.
    public mutating func record(_ identifier: String) {
        guard let tag = Self.normalized(identifier) else { return }
        current = tag
        if !all.contains(tag) { all.append(tag) }
    }

    /// The languages after `recorded` (each recording's, switch's and Undo's language, in order), for
    /// a conversation whose lines are `segments`. When every line says which language it was recognized
    /// in, `all` is exactly those languages (plus the one being recorded now), so a whole conversation
    /// transcribed again in another language no longer lists the first. Lines saved before languages
    /// were kept per line cannot say, so then nothing already listed is dropped.
    public func resolving(recorded: [String], segments: [TranscriptSegment]) -> ConversationLanguages {
        var events = self
        recorded.forEach { events.record($0) }
        var lineLanguages: [String] = []
        for tag in segments.compactMap({ $0.language.flatMap(Self.normalized) }) where !lineLanguages.contains(tag) {
            lineLanguages.append(tag)
        }
        let everyLineKnown = !segments.isEmpty && segments.allSatisfy { $0.language != nil }
        return ConversationLanguages(current: events.current,
                                     all: everyLineKnown ? lineLanguages : events.all + lineLanguages)
    }

    /// A BCP-47 tag, or nil for an empty identifier.
    public static func normalized(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tag = Locale(identifier: trimmed).identifier(.bcp47)
        return tag.isEmpty ? trimmed : tag
    }
}

public extension SessionRecord {
    /// The languages this record says it was transcribed in; empty for records saved before #206.
    var conversationLanguages: ConversationLanguages {
        ConversationLanguages(current: language, all: languages ?? [])
    }

    /// The same record with its languages replaced; `nil` fields when none are known.
    func with(languages value: ConversationLanguages) -> SessionRecord {
        SessionRecord(id: id, title: title, date: date, transcript: transcript, summary: summary,
                      segments: segments, notes: notes, quickSuggestion: quickSuggestion,
                      deepAnswer: deepAnswer, isComplete: isComplete, attachments: attachments,
                      sourceImportID: sourceImportID, titleState: titleState, language: value.current,
                      languages: value.isEmpty ? nil : value.all, selectionSummaries: selectionSummaries, summaryInstructions: summaryInstructions)
    }

    /// The same record, noting that new lines were transcribed in `identifier` (an Apple Watch file).
    func recording(language identifier: String) -> SessionRecord {
        with(languages: conversationLanguages.resolving(recorded: [identifier], segments: segments ?? []))
    }
}
