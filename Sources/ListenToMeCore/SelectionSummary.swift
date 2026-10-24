import Foundation

/// A short summary of only the transcript lines the user selected (issue #234). Saved with its
/// conversation, newest first, so the last few survive relaunch and reach exports.
public struct SelectionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    /// The first selected line's start and the last one's end, in seconds from the recording start.
    public let start: TimeInterval
    public let end: TimeInterval
    /// How many lines were selected, and whether some had to be left out to fit the model.
    public let lineCount: Int
    public let shortened: Bool
    public let text: String

    public init(id: UUID = UUID(), date: Date = Date(), start: TimeInterval, end: TimeInterval,
                lineCount: Int, shortened: Bool, text: String) {
        self.id = id; self.date = date; self.start = start; self.end = end
        self.lineCount = lineCount; self.shortened = shortened; self.text = text
    }

    /// "0:42–3:10 · 6 lines", for a heading or a notes entry.
    public var span: String {
        "\(SelectionSummaryPrompt.timestamp(start))–\(SelectionSummaryPrompt.timestamp(end)) · "
            + (lineCount == 1 ? "1 line" : "\(lineCount) lines")
    }

    /// How many are kept per conversation.
    public static let kept = 5

    /// `list` with `summary` first and only the newest `kept` entries.
    public static func remembering(_ summary: SelectionSummary, in list: [SelectionSummary]) -> [SelectionSummary] {
        Array(([summary] + list.filter { $0.id != summary.id }).prefix(kept))
    }

    /// The Markdown section exports and notes carry: one "### span" heading per summary.
    public static func markdown(_ list: [SelectionSummary]) -> String? {
        guard !list.isEmpty else { return nil }
        return list.map { "### \($0.span)\n\n\($0.text)" }.joined(separator: "\n\n")
    }
}

/// Builds the prompt for a selection summary: the selected lines with their timestamps and speaker
/// labels, fenced as data, within the provider's window. A selection that does not fit keeps its
/// opening and its latest lines (`OnDemandGrounding.select`) and says so.
public enum SelectionSummaryPrompt {
    public static let instructions = "Summarize only the selected excerpt of a conversation in 2–5 short bullets: "
        + "its main points, any decision and any stated next step. Each line starts with its time and its "
        + "speaker's label; keep names and numbers exactly as written. Use the excerpt's language. "
        + "Never invent names, owners, dates or agreements, and do not describe anything outside the excerpt. "
        + "No heading or introduction."

    public struct Built: Sendable, Equatable {
        public let request: LLMRequest
        /// The lines actually sent, in order.
        public let sent: [TranscriptSegment]
        /// True when some selected lines were left out (or the latest one cut) to fit.
        public let shortened: Bool
        /// The sheet's line when shortened, nil otherwise.
        public let notice: String?
    }

    /// The system prompt, with the data-not-instructions notice the other panes carry.
    public static var system: String { instructions + "\n" + PromptData.notice }

    /// - Parameters:
    ///   - selected: the selected lines, in transcript order.
    ///   - guidance: the session's vocabulary guidance (#222, `VocabularyPrompt.guidance`), appended to
    ///     the system prompt as every other on-demand answer gets it and charged to the same budget.
    ///   - window: the provider's prompt window in characters (Apple Intelligence), nil for none.
    /// - Returns: nil when nothing with text is selected.
    public static func build(_ selected: [TranscriptSegment], guidance: String? = nil, window: Int?) -> Built? {
        let lines = selected.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return nil }
        let fullSystem = LLMRequest(system: system, messages: []).addingGuidance(guidance).system
        let budget = OnDemandGrounding.oneShotBudget(window: window, system: fullSystem)
        // Timestamps and the fence are not part of a line's prompt cost; any overrun is taken back from
        // the lines and measured again, as `OnDemandGrounding.excerpt` does.
        var slack = lines.count * 10
        var selection = OnDemandGrounding.select(lines, budget: budget - slack, hasSummary: false)
        var message = userMessage(selection)
        while message.count > budget, slack < budget {
            slack += message.count - budget
            selection = OnDemandGrounding.select(lines, budget: budget - slack, hasSummary: false)
            message = userMessage(selection)
        }
        let shortened = selection.shape != .whole
        let left = lines.count - selection.segments.count
        let notice: String? = shortened
            ? "The selection was too long for this model, so it used the first and last selected lines"
                + (left > 0 ? " (\(left) \(left == 1 ? "line" : "lines") in between left out)." : ".")
                + (selection.latestShortened ? " The latest line was shortened." : "")
            : nil
        return Built(request: LLMRequest(system: fullSystem, messages: [ChatMessage(role: "user", content: message)]),
                     sent: selection.segments, shortened: shortened, notice: notice)
    }

    /// One selected line: "[0:42] Speaker 2: text".
    public static func line(_ segment: TranscriptSegment) -> String {
        "[\(timestamp(segment.start))] \(segment.speakerLabel): \(segment.text)"
    }

    /// "m:ss" below an hour, "h:mm:ss" from there.
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    private static func userMessage(_ selection: OnDemandGrounding.Selection) -> String {
        var message = "The user selected these lines of the conversation:\n"
            + PromptData.block("transcript", selection.segments.map(line).joined(separator: "\n"))
        if selection.shape != .whole {
            message += "\n\nThe selection was too long to send whole: these are its first and last lines; "
                + "lines in between were left out, so do not assume nothing was said there."
        }
        return message
    }
}
