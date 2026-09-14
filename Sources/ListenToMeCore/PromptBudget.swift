import Foundation

/// Bounds an assembled prompt to a provider's context window.
///
/// Providers that can take arbitrarily large prompts (Ollama, local or cloud) declare no window and
/// keep the caller's budgets untouched. Providers with a small on-device window (Apple
/// Intelligence's ~4k-token Foundation model) get every prompt clamped, so a long meeting degrades
/// to "the most recent speech" instead of a permanent context-window error (issue #119).
///
/// The split is over *assembled* characters: the caller passes the measured scaffold cost (system
/// prompt, directives, block headers, instruction — see `PromptBuilder.scaffoldCharacterCost`) and
/// this type divides what is left between transcript, references, summary and notes. Transcript
/// sizes must be charged with `TranscriptSegment.promptCharacterCost`, which includes the speaker
/// label, so hundreds of short labeled lines cannot overrun the window.
public enum PromptBudget {
    /// Prompt characters the on-device Apple Intelligence model accepts. Matches the cap iOS
    /// already enforces on its Apple summary path.
    public static let appleIntelligenceCharacters = 8_000

    /// Characters held back for the model's own answer, which shares the window with the input.
    public static let answerReserve = 1_200

    /// The transcript is never squeezed below this, even by a pathological scaffold.
    public static let minimumTranscript = 200

    /// Reference material may claim at most this fraction of what is left after summary and notes;
    /// the transcript is the reason the user is here, so an attached folder must not crowd it out.
    public static let referenceShareDivisor = 3

    /// Summary plus notes together may claim at most this fraction of what is left.
    public static let auxiliaryShareDivisor = 4

    private static let noticePrefix = "Trimmed to fit this model's context window — "

    /// A notice naming what was actually dropped, or nil when the whole prompt fit.
    /// `auxiliaryDropped` covers the user's notes and the running summary, which are grounding
    /// rather than speech and so are named separately.
    public static func truncationNotice(transcriptDropped: Bool, referencesDropped: Bool,
                                        auxiliaryDropped: Bool = false) -> String? {
        var parts: [String] = []
        if transcriptDropped { parts.append("older speech") }
        if referencesDropped { parts.append("some attached reference material") }
        if auxiliaryDropped { parts.append("your notes and the running summary") }
        guard !parts.isEmpty else { return nil }
        if parts == ["older speech"] {
            return noticePrefix + "only the most recent speech is included."
        }
        let listed: String
        switch parts.count {
        case 1:  listed = parts[0]
        case 2:  listed = parts[0] + " and " + parts[1]
        default: listed = parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
        return noticePrefix + listed + (parts.count == 1 ? " was left out." : " were left out.")
    }

    public struct Allocation: Sendable, Equatable {
        public let transcript: Int
        public let references: Int
        public let summary: Int
        public let notes: Int
        public init(transcript: Int, references: Int, summary: Int, notes: Int) {
            self.transcript = transcript
            self.references = references
            self.summary = summary
            self.notes = notes
        }
    }

    /// - Parameters:
    ///   - limit: the provider's total prompt window in characters; nil = unlimited.
    ///   - scaffold: measured cost of everything that is not transcript/reference/summary/notes text.
    ///   - transcript: transcript characters the caller would like to send (prompt cost, not raw text).
    ///   - references: reference characters available.
    ///   - summary: rolling-summary characters available.
    ///   - notes: user-note characters available.
    public static func allocate(limit: Int?, scaffold: Int = 0, transcript: Int,
                                references: Int, summary: Int = 0, notes: Int = 0) -> Allocation {
        guard let limit else {
            return Allocation(transcript: transcript, references: references,
                              summary: summary, notes: notes)
        }
        let want = { (value: Int) in max(value, 0) }
        var usable = limit - scaffold - answerReserve
        // A pathological scaffold must still leave room for some speech.
        usable = max(usable, minimumTranscript)

        // Summary and notes are grounding, not the subject: cap them jointly, letting either use
        // the other's slack.
        let auxiliaryCap = usable / auxiliaryShareDivisor
        var notesAllowance = min(want(notes), auxiliaryCap)
        let summaryAllowance = min(want(summary), auxiliaryCap - notesAllowance)
        notesAllowance = min(want(notes), auxiliaryCap - summaryAllowance)

        let remaining = max(usable - summaryAllowance - notesAllowance, 0)
        let referenceAllowance = min(want(references), remaining / referenceShareDivisor)
        let transcriptAllowance = min(want(transcript), remaining - referenceAllowance)
        return Allocation(transcript: transcriptAllowance, references: referenceAllowance,
                          summary: summaryAllowance, notes: notesAllowance)
    }
}
