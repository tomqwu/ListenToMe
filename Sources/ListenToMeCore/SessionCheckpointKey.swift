import Foundation

/// The cheap dirty key a per-second checkpoint compares *before* building a `SessionRecord`.
///
/// The autosave timer fires once a second for the whole meeting. Rebuilding the joined transcript
/// and concatenating it into a signature first made every idle tick O(total transcript length) on
/// the main actor (issue #116). `ConversationStore.revision` already changes whenever finalized
/// speech does, so it stands in for the transcript here; only the short generated outputs, the
/// title, the notes and the completion flag are compared directly.
public struct SessionCheckpointKey: Hashable, Sendable {
    public let revision: Int
    public let title: String
    public let summary: String
    public let notes: String
    public let summaryInstructions: String
    public let vocabularyDomainIDs: [String]
    public let languageOptions: ConversationLanguageOptions
    public let quickSuggestion: String
    public let deepAnswer: String
    public let complete: Bool

    public init(revision: Int, title: String, summary: String, notes: String,
                quickSuggestion: String, deepAnswer: String, complete: Bool, summaryInstructions: String = "", vocabularyDomainIDs: [String] = [],
                languageOptions: ConversationLanguageOptions = .init()) {
        self.languageOptions = languageOptions
        self.revision = revision
        self.title = title
        self.summary = summary
        self.notes = notes
        self.summaryInstructions = summaryInstructions
        self.vocabularyDomainIDs = vocabularyDomainIDs
        self.quickSuggestion = quickSuggestion
        self.deepAnswer = deepAnswer
        self.complete = complete
    }
}
