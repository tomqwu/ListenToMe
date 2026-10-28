import Foundation
import ListenToMeCore
import Observation

/// A request to summarize these lines, shown as a sheet (issue #234).
struct MobileSelectionRequest: Identifiable, Equatable {
    let id = UUID()
    let lines: [TranscriptSegment]
}

/// The one selection summary the sheet shows (issue #234). Session-only; a finished summary is also
/// saved with the conversation as a `SelectionSummary`.
///
/// Everything it shows belongs to one request in one conversation (`matches`). Preparing a request
/// clears whatever an earlier one left, and every run carries a generation token: a cancelled or
/// replaced run can never stream into, or finish, the run that followed it.
@MainActor @Observable
final class MobileSelectionRun {
    enum Phase: Equatable {
        /// Prepared; waits for the user to send it (any provider that is not on this device).
        case ready
        case running
        case finished
        /// Not sent: `message` says why (nothing to summarize, no provider, another answer running).
        case blocked
        case failed
        /// Stopped by the user; nothing is saved.
        case cancelled
    }

    private(set) var phase = Phase.ready
    private(set) var requestID: UUID?
    private(set) var conversationID: String?
    private(set) var text = ""
    private(set) var notice: String?
    /// The reason for `.blocked`, the failure for `.failed`, "Cancelled." for `.cancelled`.
    private(set) var message: String?
    /// The saved summary once the answer completed.
    private(set) var result: SelectionSummary?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var task: Task<Void, Never>?

    var isRunning: Bool { phase == .running }

    /// True when what is shown belongs to `request` in `conversation`.
    func matches(_ request: UUID, conversation: String) -> Bool {
        requestID == request && conversationID == conversation
    }

    /// A fresh state for `request`: anything an earlier request showed is gone, and its task, if one is
    /// still running, is cancelled and can no longer write here.
    func prepare(_ request: UUID, conversation: String) {
        stopTask()
        requestID = request; conversationID = conversation
        phase = .ready; text = ""; notice = nil; message = nil; result = nil
    }

    func block(_ reason: String) { stopTask(); phase = .blocked; message = reason }

    /// Starts the prepared request; the returned token identifies this run.
    func begin() -> Int {
        stopTask()
        phase = .running; text = ""; notice = nil; message = nil; result = nil
        return generation
    }

    func isCurrent(_ token: Int) -> Bool { token == generation && phase == .running }

    func stream(_ delta: String, token: Int) {
        guard isCurrent(token) else { return }
        text += delta
    }

    func finish(_ summary: SelectionSummary, notice: String?, token: Int) {
        guard isCurrent(token) else { return }
        phase = .finished; result = summary; text = summary.text; self.notice = notice; task = nil
    }

    func fail(_ failure: String, notice: String?, token: Int) {
        guard isCurrent(token) else { return }
        phase = .failed; message = failure; self.notice = notice; task = nil
    }

    /// Stops a running request. Returns true when one was running.
    @discardableResult
    func cancel() -> Bool {
        let wasRunning = isRunning
        stopTask()
        if wasRunning { phase = .cancelled; message = "Cancelled." }
        return wasRunning
    }

    private func stopTask() { generation += 1; task?.cancel(); task = nil }
}

/// Summarize just the selected transcript lines (issue #234), through the provider the user chose
/// for Summary: Apple Intelligence on this device by default, a cloud or self-hosted model only when
/// it is already the chosen summary provider — and then only after the user has seen where it goes.
///
/// A running selection summary holds `isSummarizing`, exactly like a manual Summary or Quick request,
/// so neither can start over the other and Auto's full reviews wait for it.
extension MobileSession {
    /// Why Summarize selection is unavailable for these lines, or nil when it will run.
    func selectionSummaryBlockReason(_ selected: [TranscriptSegment]) -> String? {
        if !selected.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Select one or more finished lines to summarize."
        }
        return selectionSummaryProviderBlockReason
    }

    /// Why no selection summary can run right now, whatever is selected: another answer is being
    /// written, or no provider is usable. Computed once per transcript render for every line's menu.
    var selectionSummaryProviderBlockReason: String? {
        if auxiliaryWorkSuspended || !isForeground || !applicationIsActive() {
            return "Return to ListenToMe to summarize selected lines."
        }
        if isSummarizing { return "Generating an AI response. Wait for it to finish or tap Cancel summary." }
        return summaryAvailability(for: .summary)
    }

    /// Where the selected lines are sent, said before and while they are: on this device, or the
    /// named destination of the chosen cloud, Ollama or OpenAI-compatible provider.
    var selectionSummaryDestination: String {
        selectionSummaryStaysOnDevice ? "Summarized on this device with Apple Intelligence."
            : "Sends the selected lines to \(ai.summaryEndpointLabel)."
    }

    /// True when the summary is generated on this device, so it may start without a second tap.
    var selectionSummaryStaysOnDevice: Bool { summaryProvider == nil && ai.provider == .apple }

    /// Shows `request` in a clean state (the sheet calls this as it opens). On this device it starts
    /// at once; anywhere else it waits for `startSelectionSummary` from the sheet's Summarize button.
    func prepareSelectionSummary(_ request: MobileSelectionRequest) {
        cancelSelectionSummary()   // an earlier run must not keep `isSummarizing` once replaced
        selectionRun.prepare(request.id, conversation: id)
        if let reason = selectionSummaryBlockReason(request.lines) { selectionRun.block(reason); return }
        if selectionSummaryStaysOnDevice { startSelectionSummary(request) }
    }

    /// Sends the prepared `request`. Nothing is sent when it is not the one shown, or when blocked.
    func startSelectionSummary(_ request: MobileSelectionRequest) {
        guard selectionRun.matches(request.id, conversation: id), !selectionRun.isRunning else { return }
        if let reason = selectionSummaryBlockReason(request.lines) { selectionRun.block(reason); return }
        let lines = request.lines.map(Self.promptSegment)
        // The active domain vocabulary and My terms (#222), as Quick gets them (no summary headings),
        // with the glossary ranked by what the selected lines say.
        guard let built = SelectionSummaryPrompt.build(
            lines, guidance: vocabularyGuidance(for: .quick, cloud: !selectionSummaryStaysOnDevice,
                                                heard: lines.map(\.text).joined(separator: " ")),
            window: selectionSummaryStaysOnDevice ? PromptBudget.appleIntelligenceCharacters : nil) else {
            selectionRun.block("Select one or more finished lines to summarize."); return
        }
        let token = selectionRun.begin()
        isSummarizing = true
        selectionRun.task = Task { [weak self] in
            await self?.runSelectionSummary(request.lines, built: built, token: token)
        }
    }

    /// Stops a running selection summary; the sheet then says "Cancelled." and nothing is saved.
    func cancelSelectionSummary() {
        if selectionRun.cancel() { isSummarizing = false }
    }

    /// Prepares, sends and waits for a selection summary in one step, whatever the provider (tests,
    /// and anything else that has already shown the destination).
    func summarizeSelection(_ selected: [TranscriptSegment]) async {
        let request = MobileSelectionRequest(lines: selected)
        cancelSelectionSummary()
        selectionRun.prepare(request.id, conversation: id)
        startSelectionSummary(request)
        await selectionRun.task?.value
    }

    private func runSelectionSummary(_ selected: [TranscriptSegment], built: SelectionSummaryPrompt.Built,
                                     token: Int) async {
        guard !Task.isCancelled, selectionRun.isCurrent(token), !auxiliaryWorkSuspended,
              isForeground, applicationIsActive() else { return }
        let conversation = id
        do {
            let client: any LLMProvider = try summaryProvider
                ?? (selectionSummaryStaysOnDevice ? (onDeviceProviderOverride ?? AppleIntelligenceProvider())
                    : ai.client(for: .summary))
            var cutOff = false
            var received = 0
            for try await event in client.streamEvents(built.request) {
                try Task.checkCancellation()
                guard selectionRun.isCurrent(token) else { return }
                switch event {
                case .content(let delta): selectionRun.stream(delta, token: token); received += delta.count
                case .thinking: break
                case .outputLimitReached: cutOff = true
                }
                guard received <= 20_000 else { throw RecordingError.message("The selection summary was too large.") }
            }
            try Task.checkCancellation()
            guard selectionRun.isCurrent(token) else { return }
            let text = selectionRun.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw RecordingError.message("The model returned an empty summary.") }
            let summary = SelectionSummary(start: selected.first?.start ?? 0, end: selected.last?.end ?? 0,
                                           lineCount: selected.count, shortened: built.shortened, text: text)
            let notice = [built.notice, cutOff ? LLMOutputLimit.notice : nil].compactMap { $0 }.joined(separator: " ")
            selectionRun.finish(summary, notice: notice.isEmpty ? nil : notice, token: token)
            isSummarizing = false
            // Switching conversations is blocked while this runs; the check keeps it that way.
            guard id == conversation else { return }
            selectionSummaries = SelectionSummary.remembering(summary, in: selectionSummaries)
            save(announce: false)
        } catch {
            // A cancelled or replaced run says nothing: Cancel already showed "Cancelled.".
            guard selectionRun.isCurrent(token) else { return }
            selectionRun.fail("Selection summary failed: \(MobileAISettings.errorMessage(error))",
                              notice: built.notice, token: token)
            isSummarizing = false
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
