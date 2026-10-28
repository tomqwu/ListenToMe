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
/// - a conversation that still does not fit leans on the latest summary for exactly the lines that
///   summary is known to cover, and sends the speech it does not cover as a free *head-plus-tail
///   excerpt*: the start of the uncovered speech (with no summary, the meeting's opening) and the most
///   recent speech. A summary whose coverage is unknown — cut off at the output limit, shortened to
///   fit, or restored from disk — is still included, but is never claimed to cover anything. No extra
///   model call is made;
/// - the selected lines never cost more than the budget: the opening goes first, then the latest
///   line is shortened to its most recent words;
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
    /// The start of the uncovered speech gets at most this fraction of an excerpt; the most recent
    /// speech gets the rest.
    public static let openingShareDivisor = 4
    /// Prompt characters held back for `Selection.promptNote` and its separator; every note fits.
    public static let promptNoteReserve = 640
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

    /// How many leading lines a summary covers: the longest prefix of `segments` whose IDs are in
    /// `ids`. A summary covers what its request read; speech after it, or lines that were replaced
    /// (re-transcribed, so with new IDs), are not covered.
    public static func coveredPrefix(of segments: [TranscriptSegment], ids: Set<UUID>) -> Int {
        segments.prefix { ids.contains($0.id) }.count
    }

    public enum Shape: Sendable, Equatable {
        /// Every line fits.
        case whole
        /// Only the most recent speech.
        case recent
        /// The start of the uncovered speech (with no summary, the opening) plus the most recent speech.
        case openingAndRecent
        /// The summary covers the leading lines, and everything said since is sent.
        case summaryAndRecent
    }

    public struct Selection: Sendable, Equatable {
        /// The lines to send, in order: the head (if any) then the most recent speech.
        public let segments: [TranscriptSegment]
        public let shape: Shape
        /// How many of `segments` are the head: the opening, or the speech right after the summary.
        public let openingCount: Int
        /// Leading lines the summary stands in for, which are not sent; 0 when no summary covers any.
        public let coveredCount: Int
        /// A summary is sent whose coverage is unknown, so it is never claimed to cover anything.
        public let unverifiedSummary: Bool
        /// The latest line was shortened to its most recent words to fit.
        public let latestShortened: Bool
        public let coveredMinutes: Int
        public let openingMinutes: Int
        public let recentMinutes: Int
        public let omittedMinutes: Int

        /// One line for the pane, or nil when every line was sent whole. `summaryName` is what the
        /// platform calls its summary ("the Listener summary", "your Summary").
        public func notice(summaryName: String) -> String? {
            guard shape != .whole else { return nil }
            let covered = coveredCount > 0
            var text = "Using "
            if covered { text += "\(summaryName) of the first ~\(coveredMinutes) min" }
            switch shape {
            case .whole: return nil
            case .summaryAndRecent:
                text += " and everything said since (~\(recentMinutes) min)"
            case .openingAndRecent:
                text += covered ? ", the ~\(openingMinutes) min after it and the last ~\(recentMinutes) min"
                    : "the opening ~\(openingMinutes) min and the last ~\(recentMinutes) min"
                text += " of the conversation"
            case .recent:
                text += (covered ? " and " : "") + "the last ~\(recentMinutes) min of the conversation"
            }
            if omittedMinutes > 0 { text += " (~\(omittedMinutes) min in between left out)" }
            text += "."
            if latestShortened { text += " The latest line was shortened." }
            if unverifiedSummary { text += " An earlier summary is included too." }
            return text
        }

        /// The app's own explanation for the model, placed outside the transcript fence; nil when
        /// every line was sent whole. Never longer than `promptNoteReserve` minus its separator.
        public var promptNote: String? {
            guard shape != .whole else { return nil }
            var parts: [String] = []
            if coveredCount > 0 {
                parts.append("The meeting summary covers the first \(coveredCount) lines (~\(coveredMinutes) min) of "
                    + "the meeting; they are not repeated in the transcript.")
            }
            switch shape {
            case .whole: break
            case .summaryAndRecent: parts.append("The transcript holds everything said after that.")
            case .openingAndRecent:
                parts.append("The transcript's first \(openingCount) lines are "
                    + (coveredCount > 0 ? "the speech right after the summary" : "the opening of the meeting")
                    + " and the rest is the most recent speech.")
            case .recent: parts.append("The transcript holds only the most recent ~\(recentMinutes) min.")
            }
            if omittedMinutes > 0 {
                parts.append("About \(omittedMinutes) min of speech before the most recent part was left out to fit, "
                    + "so do not assume nothing was said there.")
            }
            if latestShortened { parts.append("Its latest line was shortened to its most recent words.") }
            if unverifiedSummary {
                parts.append("The summary is from earlier in the meeting and may not cover the speech left out.")
            }
            return parts.joined(separator: " ")
        }
    }

    /// Chooses the lines an on-demand answer reads, within `budget` prompt characters (charged with
    /// `TranscriptSegment.promptCharacterCost`) — never more.
    ///
    /// - Parameters:
    ///   - hasSummary: a summary is sent with the prompt.
    ///   - coveredCount: the leading lines that summary is known to cover (see `coveredPrefix`); 0
    ///     when its coverage is unknown, in which case it is sent but never claimed to cover anything.
    public static func select(_ segments: [TranscriptSegment], budget: Int, hasSummary: Bool,
                              coveredCount: Int = 0) -> Selection {
        let cost = TranscriptSegment.promptCharacterCost
        let budget = max(0, budget)
        let total = segments.reduce(0) { $0 + cost($1) }
        guard total > budget, !segments.isEmpty else {
            return Selection(segments: segments, shape: .whole, openingCount: 0, coveredCount: 0,
                             unverifiedSummary: false, latestShortened: false, coveredMinutes: 0,
                             openingMinutes: 0, recentMinutes: minutes(segments), omittedMinutes: 0)
        }
        let covered = hasSummary ? min(max(0, coveredCount), segments.count) : 0
        // The summary stands in for the lines it covers; what it does not cover is the material. When
        // it covers everything, the latest lines are still sent verbatim.
        let start = covered < segments.count ? covered : max(0, segments.count - 1)
        let uncovered = Array(segments[start...])
        let uncoveredCost = uncovered.reduce(0) { $0 + cost($1) }

        var head: [TranscriptSegment] = []
        var tail: [TranscriptSegment] = []
        var shortened = false
        if uncoveredCost <= budget {
            tail = uncovered
        } else {
            // The head is the start of what no summary covers: the opening with no summary (or one of
            // unknown coverage), otherwise the speech right after the summary's coverage.
            var headCost = 0
            for segment in uncovered.dropLast() {
                let next = cost(segment)
                guard headCost + next <= budget / openingShareDivisor else { break }
                head.append(segment); headCost += next
            }
            tail = fill(uncovered.dropFirst(head.count), budget: budget - headCost)
            if tail.isEmpty {
                // The latest line does not fit beside the head: the head goes first, then the latest
                // line keeps its most recent words.
                head = []
                tail = fill(uncovered[...], budget: budget)
                if tail.isEmpty, let latest = uncovered.last, let trimmed = shortenedLine(latest, to: budget) {
                    tail = [trimmed]; shortened = true
                }
            }
        }
        let omitted = Array(uncovered.dropFirst(head.count).dropLast(tail.count))
        // Every line before `start` is covered by the summary (when it covers everything, `start`
        // keeps the latest line verbatim), so those are what the notice may claim.
        let coveredShown = covered > 0 ? start : 0
        let shape: Shape
        if !omitted.isEmpty || shortened { shape = head.isEmpty ? .recent : .openingAndRecent }
        else if coveredShown > 0 { shape = .summaryAndRecent }
        else { shape = .recent }
        return Selection(segments: head + tail, shape: shape, openingCount: head.count,
                         coveredCount: coveredShown, unverifiedSummary: hasSummary && covered == 0,
                         latestShortened: shortened,
                         coveredMinutes: minutes(Array(segments[..<coveredShown])),
                         openingMinutes: minutes(head), recentMinutes: minutes(tail),
                         omittedMinutes: minutes(omitted))
    }

    /// The most recent whole lines of `lines` that fit `budget`, in order; empty when even the latest
    /// one does not.
    private static func fill(_ lines: ArraySlice<TranscriptSegment>, budget: Int) -> [TranscriptSegment] {
        var kept: [TranscriptSegment] = []
        var spent = 0
        for segment in lines.reversed() {
            let next = TranscriptSegment.promptCharacterCost(segment)
            guard spent + next <= budget else { break }
            kept.append(segment); spent += next
        }
        return kept.reversed()
    }

    /// `segment` cut to its most recent words so its prompt cost fits `budget`; nil when not even a
    /// few words fit beside its label.
    private static func shortenedLine(_ segment: TranscriptSegment, to budget: Int) -> TranscriptSegment? {
        let tag = !segment.isFinal && segment.text.hasPrefix(ConversationStore.provisionalTag)
            ? ConversationStore.provisionalTag : ""
        let allowance = budget - segment.speakerLabel.count - 3 - tag.count
        guard allowance >= (tag.isEmpty ? 8 : ConversationStore.provisionalMinimumCharacters) else { return nil }
        let text = tag + String(segment.text.dropFirst(tag.count).suffix(allowance))
        return TranscriptSegment(id: segment.id, source: segment.source, text: text,
                                 isFinal: segment.isFinal, start: segment.start, end: segment.end,
                                 speakerID: segment.speakerID, speakerName: segment.speakerName,
                                 originalText: segment.originalText, correctionModel: segment.correctionModel,
                                 language: segment.language, recordingID: segment.recordingID)
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
        /// True when only the end of the summary — its decisions and actions — fit.
        public internal(set) var summaryShortened = false
        /// The panel's line: which speech was read, and what had to be shortened.
        public func notice(summaryName: String) -> String? {
            let parts = [selection.notice(summaryName: summaryName),
                         summaryShortened ? "Only the end of the summary fit." : nil,
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

    /// Fits notes, transcript and summary into `budget` characters of user message — never more.
    /// Everything is sent when it fits. Otherwise notes keep what the speech leaves (at least a
    /// quarter), the summary keeps its end — its decisions and actions — within a third, and the lines
    /// get the rest. `summaryCoveredIDs` are the lines the summary was generated from.
    public static func excerpt(notes: String, segments: [TranscriptSegment], summary: String,
                               summaryCoveredIDs: Set<UUID> = [], budget: Int) -> Excerpt {
        let notesLine = QuickSummaryContext.attributedNotes(notes)
        let whole = render(select(segments, budget: .max, hasSummary: false), notes: notesLine, summary: nil)
        if whole.userMessage.count <= budget { return whole }
        // Fencing escapes "</" one character at a time, which no line cost counts; a rare overrun is
        // taken back from the lines and measured again.
        var slack = 0
        var excerpt = fitted(notesLine: notesLine, segments: segments, summary: summary,
                             summaryCoveredIDs: summaryCoveredIDs, budget: budget, slack: slack)
        while excerpt.userMessage.count > budget, slack < budget {
            slack += excerpt.userMessage.count - budget
            excerpt = fitted(notesLine: notesLine, segments: segments, summary: summary,
                             summaryCoveredIDs: summaryCoveredIDs, budget: budget, slack: slack)
        }
        return excerpt
    }

    private static func fitted(notesLine: String, segments: [TranscriptSegment], summary: String,
                               summaryCoveredIDs: Set<UUID>, budget: Int, slack: Int) -> Excerpt {
        let fence = PromptData.block("transcript", "").count
        let linesCost = segments.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) }
        // Notes get whatever the speech does not need, and at least a quarter.
        let notesRoom = max(budget / 4, budget - fence - linesCost - 1)
        let keptNotes = String(notesLine.prefix(max(0, notesRoom)))
        let notesCost = keptNotes.isEmpty ? 0 : keptNotes.count + 1
        let lineBudget = budget - fence - notesCost - slack
        if linesCost <= lineBudget {
            var excerpt = render(select(segments, budget: .max, hasSummary: false), notes: keptNotes, summary: nil)
            excerpt.notesShortened = keptNotes.count < notesLine.count
            return excerpt
        }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryOverhead = 2 + Excerpt.summaryHeader.count + PromptData.block("summary", "").count
        let summaryRoom = max(0, budget / 3 - summaryOverhead)
        let keptSummary = trimmedSummary.isEmpty || summaryRoom == 0 ? nil : String(trimmedSummary.suffix(summaryRoom))
        let summaryShortened = keptSummary.map { $0.count < trimmedSummary.count } ?? false
        let summaryCost = keptSummary.map { $0.count + summaryOverhead } ?? 0
        // A summary that had to be shortened, like one generated from other lines, covers nothing for sure.
        let covered = keptSummary == nil || summaryShortened ? 0 : coveredPrefix(of: segments, ids: summaryCoveredIDs)
        let selection = select(segments, budget: lineBudget - summaryCost - promptNoteReserve,
                               hasSummary: keptSummary != nil, coveredCount: covered)
        var excerpt = render(selection, notes: keptNotes, summary: selection.shape == .whole ? nil : keptSummary)
        excerpt.notesShortened = keptNotes.count < notesLine.count
        excerpt.summaryShortened = excerpt.summary != nil && summaryShortened
        return excerpt
    }

    private static func render(_ selection: Selection, notes: String, summary: String?) -> Excerpt {
        let lines = selection.segments.map(QuickSummaryContext.attributed)
        let transcript = ([notes] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
        return Excerpt(transcript: transcript, summary: summary, selection: selection)
    }
}
