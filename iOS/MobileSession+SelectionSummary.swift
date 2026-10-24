import Foundation
import ListenToMeCore
import Observation

/// One selection summary while it is generated and shown (issue #234). Session-only; a finished
/// summary is saved with the conversation as a `SelectionSummary`.
@MainActor @Observable
final class MobileSelectionRun {
    private(set) var isRunning = false
    private(set) var text = ""
    private(set) var notice: String?
    private(set) var error: String?
    /// The saved summary once the answer completed.
    private(set) var result: SelectionSummary?
    @ObservationIgnored var task: Task<Void, Never>?

    func begin() { isRunning = true; text = ""; notice = nil; error = nil; result = nil }
    func stream(_ delta: String) { text += delta }
    func finish(_ summary: SelectionSummary?, notice: String?, error: String?) {
        isRunning = false; result = summary; self.notice = notice; self.error = error
        if let summary { text = summary.text }
    }
    func cancel() { task?.cancel(); task = nil }
}

/// Summarize just the selected transcript lines (issue #234), through the provider the user chose
/// for Summary: Apple Intelligence on this device by default, a cloud or self-hosted model only when
/// it is already the chosen summary provider.
extension MobileSession {
    /// Why Summarize selection is unavailable for these lines, or nil when it will run.
    func selectionSummaryBlockReason(_ selected: [TranscriptSegment]) -> String? {
        if selected.isEmpty { return "Select one or more finished lines to summarize." }
        if isSummarizing || selectionRun.isRunning {
            return "Generating an AI response. Wait for it to finish or tap Cancel summary."
        }
        return summaryAvailability(for: .summary)
    }

    /// Where the selected lines are sent, said before and while they are: on this device, or the
    /// named destination of the chosen cloud or OpenAI-compatible provider.
    var selectionSummaryDestination: String {
        summaryUsesThisDevice ? "Summarized on this device with Apple Intelligence."
            : "Sends the selected lines to \(ai.summaryEndpointLabel)."
    }

    private var summaryUsesThisDevice: Bool { summaryProvider == nil && ai.provider == .apple }

    /// Starts a selection summary; the sheet observes `selectionRun`. Nothing is sent when blocked.
    func requestSelectionSummary(_ selected: [TranscriptSegment]) {
        if let reason = selectionSummaryBlockReason(selected) {
            selectionRun.finish(nil, notice: nil, error: reason); return
        }
        selectionRun.cancel()
        selectionRun.task = Task { await summarizeSelection(selected) }
    }

    func summarizeSelection(_ selected: [TranscriptSegment]) async {
        let lines = selected.map(Self.promptSegment)
        // TODO(#222): pass the active domain vocabulary once it lands.
        guard let built = SelectionSummaryPrompt.build(
            lines, window: summaryUsesThisDevice ? PromptBudget.appleIntelligenceCharacters : nil) else {
            selectionRun.finish(nil, notice: nil, error: "Select one or more lines with words to summarize.")
            return
        }
        selectionRun.begin()
        let conversation = id
        do {
            let client: any LLMProvider = try summaryProvider
                ?? (summaryUsesThisDevice ? (onDeviceProviderOverride ?? AppleIntelligenceProvider())
                    : ai.client(for: .summary))
            var cutOff = false
            for try await event in client.streamEvents(built.request) {
                try Task.checkCancellation()
                switch event {
                case .content(let delta): selectionRun.stream(delta)
                case .thinking: break
                case .outputLimitReached: cutOff = true
                }
                guard selectionRun.text.count <= 20_000 else {
                    throw RecordingError.message("The selection summary was too large.")
                }
            }
            try Task.checkCancellation()
            let text = selectionRun.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw RecordingError.message("The model returned an empty summary.") }
            let summary = SelectionSummary(start: selected.first?.start ?? 0, end: selected.last?.end ?? 0,
                                           lineCount: selected.count, shortened: built.shortened, text: text)
            let notice = [built.notice, cutOff ? LLMOutputLimit.notice : nil].compactMap { $0 }.joined(separator: " ")
            selectionRun.finish(summary, notice: notice.isEmpty ? nil : notice, error: nil)
            // A summary of another conversation's lines is shown but never saved into this one.
            guard id == conversation else { return }
            selectionSummaries = SelectionSummary.remembering(summary, in: selectionSummaries)
            save(announce: false)
        } catch {
            selectionRun.finish(nil, notice: built.notice,
                                error: "Selection summary failed: \(MobileAISettings.errorMessage(error))")
        }
    }

    /// Appends a selection summary to the conversation's notes under its time span.
    func addSelectionSummaryToNotes(_ summary: SelectionSummary) {
        let entry = "Selection summary (\(summary.span)):\n\(summary.text)"
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry : notes + "\n\n" + entry
        save(announce: false)
        message = "Selection summary added to notes."
    }
}
