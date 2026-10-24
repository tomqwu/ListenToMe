import Foundation

/// What an on-demand Quick or Deep answer is grounded in when Auto is off (issue #114).
///
/// Auto is off by default, so there is often no summary yet when the user presses the hotkey. Until
/// this type, such an answer saw a fixed 4,000 characters of the most recent speech (about four
/// minutes), and nothing said so. Now:
///
/// - the transcript budget scales with the provider: as much as fits for a provider with a declared
///   window (Apple Intelligence, about 4k tokens), and a larger fixed budget for Ollama and cloud
///   models, which declare none;
/// - a conversation that still does not fit keeps the *latest summary* plus the most recent speech
///   when a summary exists, and otherwise a free *head-plus-tail excerpt*: the meeting's opening
///   (agenda, introductions, the first decisions) and the most recent speech. No extra model call;
/// - the excerpt is explained to the model in an app-written note outside the transcript fence, and
///   to the user in a one-line notice such as "Using the last ~5 min of the conversation."
///
/// Pure and provider-independent, so both platforms share it; `PromptBudget` still bounds the
/// assembled prompt to the provider's window.
public enum OnDemandGrounding {
    /// Transcript characters a Quick answer asks for from a provider with no declared window: about
    /// 18 minutes of speech, small enough to keep a hotkey answer quick on a local model.
    public static let quickTranscriptCharacters = 16_000
    /// The same for Deep, which is deliberate and can afford twice the reading.
    public static let deepTranscriptCharacters = 32_000
    /// Actions that cover the whole conversation (a recap, every action item so far).
    public static let wholeConversationCharacters = 100_000
    /// The opening gets at most this fraction of an excerpt; the most recent speech gets the rest.
    public static let openingShareDivisor = 4
    /// Prompt characters held back for `Selection.promptNote` and its separator; every note fits.
    public static let promptNoteReserve = 360
    /// Speech rate for lines without usable timestamps: the issue's 4,000 characters ≈ 4-5 minutes.
    static let charactersPerMinute = 850

    /// The transcript characters to ask for. `limit` is the provider's prompt window (nil = none);
    /// with a window the whole of it is requested and `PromptBudget.allocate` decides what fits.
    public static func transcriptBudget(for action: ResponseAction, kind: PromptBuilder.Kind, limit: Int?) -> Int {
        switch action {
        case .recap, .actionItems: return wholeConversationCharacters
        default: break
        }
        if let limit { return limit }
        return kind == .deep ? deepTranscriptCharacters : quickTranscriptCharacters
    }

    public enum Shape: Sendable, Equatable {
        /// Every line fits.
        case whole
        /// Only the most recent speech (no summary, and no room for the opening as well).
        case recent
        /// The meeting's opening plus the most recent speech.
        case openingAndRecent
        /// The latest summary covers the earlier part; the transcript is the most recent speech.
        case summaryAndRecent
    }

    public struct Selection: Sendable, Equatable {
        /// The finalized lines to send, in order: the opening (if any) then the most recent speech.
        public let segments: [TranscriptSegment]
        public let shape: Shape
        /// How many of `segments` are the opening.
        public let openingCount: Int
        public let openingMinutes: Int
        public let recentMinutes: Int
        public let omittedMinutes: Int

        /// One line for the pane, or nil when the whole conversation was used. `summaryName` is what
        /// the platform calls the summary it reused ("the Listener summary", "your Summary").
        public func notice(summaryName: String) -> String? {
            switch shape {
            case .whole: return nil
            case .recent: return "Using the last ~\(recentMinutes) min of the conversation."
            case .summaryAndRecent: return "Using \(summaryName) and the last ~\(recentMinutes) min of the conversation."
            case .openingAndRecent:
                return "Using the opening ~\(openingMinutes) min and the last ~\(recentMinutes) min of the "
                    + "conversation (~\(omittedMinutes) min in between left out)."
            }
        }

        /// The app's own explanation for the model, placed outside the transcript fence; nil when the
        /// whole conversation was used. Never longer than `promptNoteReserve` minus its separator.
        public var promptNote: String? {
            switch shape {
            case .whole: return nil
            case .recent:
                return "The transcript holds only the most recent ~\(recentMinutes) min of the meeting; "
                    + "earlier speech was left out to fit, so do not assume nothing was said before it."
            case .summaryAndRecent:
                return "The transcript holds only the most recent ~\(recentMinutes) min of the meeting; "
                    + "the meeting summary covers what came before it."
            case .openingAndRecent:
                return "The transcript is an excerpt: its first \(openingCount) lines are the opening of the "
                    + "meeting and the rest is the most recent speech. About \(omittedMinutes) min of speech in "
                    + "between was left out to fit, so do not assume nothing was said there."
            }
        }
    }

    /// Chooses the lines an on-demand answer reads, within `budget` prompt characters (charged with
    /// `TranscriptSegment.promptCharacterCost`). The most recent line is always kept, as
    /// `ConversationStore.recentContext` always kept it.
    public static func select(_ segments: [TranscriptSegment], budget: Int, hasSummary: Bool) -> Selection {
        let cost = TranscriptSegment.promptCharacterCost
        let total = segments.reduce(0) { $0 + cost($1) }
        guard total > budget, !segments.isEmpty else {
            return Selection(segments: segments, shape: .whole, openingCount: 0,
                             openingMinutes: 0, recentMinutes: minutes(segments), omittedMinutes: 0)
        }
        // The opening is worth keeping only when nothing else describes it.
        var opening: [TranscriptSegment] = []
        var openingCost = 0
        if !hasSummary {
            let openingBudget = budget / openingShareDivisor
            for segment in segments.dropLast() {
                let next = cost(segment)
                guard openingCost + next <= openingBudget else { break }
                opening.append(segment); openingCost += next
            }
        }
        var recent: [TranscriptSegment] = []
        var recentCost = 0
        for segment in segments.dropFirst(opening.count).reversed() {
            let next = cost(segment)
            if !recent.isEmpty && recentCost + next > budget - openingCost { break }
            recent.append(segment); recentCost += next
        }
        recent.reverse()
        let omitted = Array(segments[opening.count..<(segments.count - recent.count)])
        // Only an oversized latest line can leave nothing out; everything is then sent.
        guard !omitted.isEmpty else {
            return Selection(segments: segments, shape: .whole, openingCount: 0,
                             openingMinutes: 0, recentMinutes: minutes(segments), omittedMinutes: 0)
        }
        let shape: Shape = hasSummary ? .summaryAndRecent : (opening.isEmpty ? .recent : .openingAndRecent)
        return Selection(segments: opening + recent, shape: shape, openingCount: opening.count,
                         openingMinutes: minutes(opening), recentMinutes: minutes(recent),
                         omittedMinutes: minutes(omitted))
    }

    /// Whole minutes the lines span, at least 1: from their timestamps when those describe a span,
    /// otherwise estimated from their length.
    static func minutes(_ segments: [TranscriptSegment]) -> Int {
        guard let first = segments.first, let last = segments.last else { return 0 }
        let span = last.end - first.start
        if span > 0 { return max(1, Int((span / 60).rounded())) }
        let characters = segments.reduce(0) { $0 + $1.text.count }
        return max(1, Int((Double(characters) / Double(charactersPerMinute)).rounded()))
    }
}

extension OnDemandGrounding {
    /// The user message of a one-shot on-demand answer (the iOS Quick and Deep panes): the user's
    /// notes and the selected lines, fenced as data, then the app's excerpt note and — only when the
    /// conversation did not fit — the summary the user already has.
    public struct Excerpt: Sendable, Equatable {
        /// Notes line plus the selected transcript lines, unfenced: the evaluator envelope takes this.
        public let transcript: String
        /// The reused summary, or nil when the whole conversation fit or there was none.
        public let summary: String?
        public let selection: Selection
        /// True when the user's notes had to be cut to leave room for speech.
        public internal(set) var notesShortened = false
        /// The panel's line: which speech was read, and whether the notes were shortened.
        public func notice(summaryName: String) -> String? {
            let parts = [selection.notice(summaryName: summaryName),
                         notesShortened ? "Your notes were shortened to fit." : nil].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        /// The fenced message for a plain chat prompt.
        public var userMessage: String {
            var message = PromptData.block("transcript", transcript)
            if let note = selection.promptNote { message += "\n\n" + note }
            if let summary { message += "\n\n" + Self.summaryHeader + PromptData.block("summary", summary) }
            return message
        }
        static let summaryHeader = "Summary of the conversation so far:\n"
    }

    /// Characters a one-shot prompt has a provider with no declared window send (the iOS cloud cap).
    public static let oneShotCharacters = 60_000

    /// User-message characters for a one-shot answer: what `window` leaves after the system prompt
    /// and the answer's reserve, or `oneShotCharacters` for a provider with no window.
    public static func oneShotBudget(window: Int?, system: String) -> Int {
        guard let window else { return oneShotCharacters }
        return max(PromptBudget.minimumTranscript, window - PromptBudget.answerReserve - system.count)
    }

    /// Fits notes and transcript into `budget` characters of user message. Everything is sent when it
    /// fits. Otherwise notes may take a quarter and the reused summary another quarter, and the lines
    /// get the rest.
    public static func excerpt(notes: String, segments: [TranscriptSegment], summary: String, budget: Int) -> Excerpt {
        let fence = PromptData.block("transcript", "").count
        let notesLine = QuickSummaryContext.attributedNotes(notes)
        func render(_ selection: Selection, notes: String, summary: String?) -> Excerpt {
            let lines = selection.segments.map(QuickSummaryContext.attributed)
            let transcript = ([notes] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
            return Excerpt(transcript: transcript, summary: summary, selection: selection)
        }
        let whole = render(select(segments, budget: .max, hasSummary: false), notes: notesLine, summary: nil)
        if whole.userMessage.count <= budget { return whole }
        let keptNotes = String(notesLine.prefix(max(0, budget / 4)))
        let notesCost = keptNotes.isEmpty ? 0 : keptNotes.count + 1
        let lineBudget = budget - fence - notesCost
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryOverhead = 2 + Excerpt.summaryHeader.count + PromptData.block("summary", "").count
        let keptSummary = trimmedSummary.isEmpty ? nil : String(trimmedSummary.prefix(max(0, budget / 4 - summaryOverhead)))
        let summaryCost = keptSummary.map { $0.count + summaryOverhead } ?? 0
        let selection = select(segments, budget: lineBudget - summaryCost - promptNoteReserve,
                               hasSummary: keptSummary?.isEmpty == false)
        // Every line fitting once the notes were shortened needs no summary to stand in for speech.
        let reused = selection.shape == .whole || keptSummary?.isEmpty != false ? nil : keptSummary
        var excerpt = render(selection, notes: keptNotes, summary: reused)
        excerpt.notesShortened = keptNotes.count < notesLine.count
        return excerpt
    }
}
