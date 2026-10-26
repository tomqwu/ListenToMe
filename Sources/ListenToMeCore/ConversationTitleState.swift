import Foundation

/// Where a conversation's title came from (#221), saved with its record so an automatic title never
/// replaces one the user typed or one Load from Calendar set.
public struct ConversationTitleState: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// The default name: "New conversation", "Conversation — <date>", "Apple Watch · <date>".
        case placeholder
        /// Named automatically after a save.
        case automatic
        /// Typed or edited by the user.
        case user
        /// Set from a calendar event.
        case calendar
    }

    public var source: Source
    /// Final-transcript words when the title was named automatically, for a later refinement.
    public var automaticWords: Int?
    /// The automatic title was refined once already; it is not changed again.
    public var refined: Bool?
    /// Final-transcript words when naming last produced nothing, so it is not tried again on every
    /// Save or return to the app until the conversation has grown (see `ConversationAutoTitle.shouldName`).
    public var attemptedWords: Int?

    public init(source: Source, automaticWords: Int? = nil, refined: Bool? = nil, attemptedWords: Int? = nil) {
        self.source = source
        self.automaticWords = automaticWords
        self.refined = refined
        self.attemptedWords = attemptedWords
    }

    public static let placeholder = ConversationTitleState(source: .placeholder)
    public static let user = ConversationTitleState(source: .user)
    public static let calendar = ConversationTitleState(source: .calendar)

    public static func automatic(words: Int, refined: Bool = false) -> ConversationTitleState {
        ConversationTitleState(source: .automatic, automaticWords: words, refined: refined ? true : nil)
    }

    /// A record saved before #221 has no state. It counts as still having its default name only when
    /// the title is exactly one the app generated: "New conversation", or "Apple Watch · " /
    /// "Conversation — " followed by a date that parses back. Anything else, including "Imported
    /// notes" and a date in a format this device no longer reads, is treated as the user's: an old
    /// default may then keep its name, but a title someone chose is never renamed.
    public static func resolved(_ state: ConversationTitleState?, title: String) -> ConversationTitleState {
        state ?? (ConversationTitle.isLegacyDefault(title) ? .placeholder : .user)
    }

    private enum CodingKeys: String, CodingKey { case source, automaticWords, refined, attemptedWords }

    /// A source written by a newer version decodes as `.user`, so it is never overwritten and the
    /// record still opens.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .source) ?? Source.user.rawValue
        source = Source(rawValue: raw) ?? .user
        automaticWords = try? container.decodeIfPresent(Int.self, forKey: .automaticWords)
        refined = try? container.decodeIfPresent(Bool.self, forKey: .refined)
        attemptedWords = try? container.decodeIfPresent(Int.self, forKey: .attemptedWords)
    }
}

public extension SessionRecord {
    /// Where this record's title came from, including records saved before #221.
    var resolvedTitleState: ConversationTitleState { .resolved(titleState, title: title) }

    /// The same record under a new title. Every other field is kept.
    func retitled(_ newTitle: String, state: ConversationTitleState) -> SessionRecord {
        SessionRecord(id: id, title: newTitle, date: date, transcript: transcript, summary: summary,
                      segments: segments, notes: notes, quickSuggestion: quickSuggestion, deepAnswer: deepAnswer,
                      isComplete: isComplete, attachments: attachments, sourceImportID: sourceImportID,
                      titleState: state, language: language, languages: languages,
                      selectionSummaries: selectionSummaries, summaryInstructions: summaryInstructions, vocabularyDomainIDs: vocabularyDomainIDs,
                      hasIncompleteImport: hasIncompleteImport, situationGrid: situationGrid)
    }
}
