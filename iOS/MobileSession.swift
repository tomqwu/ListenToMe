import Foundation
import FoundationModels
import ListenToMeCore
import Observation
import UIKit

@MainActor @Observable
final class MobileSession {
    enum State { case idle, preparing, recording, stopping }
    var state = State.idle { didSet { handleSummaryEvent(.recordingChanged) } }
    var title = "New conversation"
    var notes = "" { didSet { handleSummaryEvent(.notesChanged) } }
    var summary = ""
    var quickSummary = ""
    var deepThought = ""
    var attachments: [SessionAttachment] = []
    var generatingMode: MobileSummaryMode?
    var autoQuick = UserDefaults.standard.bool(forKey: "autoQuickSummary") {
        didSet { UserDefaults.standard.set(autoQuick, forKey: "autoQuickSummary"); handleSummaryEvent(.automationChanged) }
    }
    let quickReader = MobileQuickReader()
    let automaticReviews = AutomaticReviewCoordinator()
    private(set) var speechEventCount = 0
    private(set) var finalizedSpeechEventCount = 0
    private(set) var quickWakeCount = 0
    private(set) var quickEvaluationCount = 0
    private(set) var lastSpeechEvent: Date?
    var quickDiagnostics: String {
        [autoQuickStatus, "Recording: \(state == .recording ? "yes" : "no")",
         "Speech events: \(speechEventCount) (final: \(finalizedSpeechEventCount))",
         "Last speech: \(lastSpeechEvent?.formatted(date: .omitted, time: .standard) ?? "none")",
         "Scheduled checks fired: \(quickWakeCount)", "Model checks started: \(quickEvaluationCount)",
         "Completed reads: \(quickReader.completedReads)",
         "Unread speech: \(quickReader.context.hasChanges(quickPieces) ? "yes" : "no")",
         "Provider: \(automaticQuickAvailability ?? "available")",
         quickSummaryError ?? "No summary error"].joined(separator: "\n")
    }
    private var quickScheduler: MobileSummaryScheduler
    private var autoTask: Task<Void, Never>?
    private let summaryProvider: (any LLMProvider)?
    /// The on-device transport used when the provider is Apple Intelligence. Only tests replace it,
    /// so the simulator can exercise the on-device path without an Apple Intelligence capable host.
    var onDeviceProviderOverride: (any LLMProvider)?
    let correctionProvider: (any LLMProvider)?
    let speechCorrection = MobileTranscriptCorrector()
    var acceptsSpeechCorrection = false
    private let makeRecorder: () -> any MobileRecording
    private var manualQuickError: String?
    var quickSummaryError: String? { manualQuickError ?? quickReader.error }
    private var sourceImportID: String?
    var segments: [TranscriptSegment] = [] { didSet { scheduleAutoQuick() } }
    var partial: TranscriptSegment?
    var history: [SessionRecord] = []
    var message: String?
    var isSummarizing = false { didSet { synchronizeAutomaticReviews() } }
    let ai = MobileAISettings()
    var summaryDraft = ""
    private var summaryTask: Task<Void, Never>?
    var language = Locale.current.identifier
    private(set) var id = UUID().uuidString
    private var date = Date()
    private var recorder: (any MobileRecording)?
    private var startTask: Task<Void, Never>?
    private let archive: SessionArchive
    private let activeURL: URL
    let attachmentRoot: URL

    init(storageDirectory: URL = .applicationSupportDirectory,
         summaryProvider: (any LLMProvider)? = nil, autoInterval: Duration = .seconds(5),
         correctionProvider: (any LLMProvider)? = nil,
         makeRecorder: @escaping () -> any MobileRecording = { MobileRecorder() }) {
        self.summaryProvider = summaryProvider
        self.correctionProvider = correctionProvider
        quickScheduler = MobileSummaryScheduler(interval: autoInterval)
        self.makeRecorder = makeRecorder
        activeURL = storageDirectory.appendingPathComponent("ActiveConversation.json")
        attachmentRoot = storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        let directory = storageDirectory.appendingPathComponent("Conversations", isDirectory: true)
        archive = SessionArchive(directory: directory)
        refreshHistory()
        if FileManager.default.fileExists(atPath: activeURL.path) {
            do { restore(try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: activeURL))) }
            catch { message = "Could not restore the current conversation: \(error.localizedDescription). Check History." }
        } else if let latest = history.first { restore(latest) }
        ai.correctionSettingsChanged = { [weak self] in self?.speechCorrection.cancel() }
        ai.quickSettingsChanged = { [weak self] in
            guard let self else { return }
            self.quickReader.clearError()
            self.handleSummaryEvent(.providerChanged)
        }
    }

    var busy: Bool { state != .idle || isSummarizing }
    var hasContent: Bool {
        !segments.isEmpty || partial != nil || !notes.isEmpty || !summary.isEmpty
            || !quickSummary.isEmpty || !deepThought.isEmpty || !attachments.isEmpty
    }
    var allSegments: [TranscriptSegment] { segments + (partial.map { [$0] } ?? []) }
    var markdown: String {
        let text = SessionExporter.markdown(title: title, transcript: allSegments, notes: notes, listenerSummary: summary,
                                            quickSuggestion: quickSummary, deepAnswer: deepThought)
        return text + (attachments.isEmpty ? "" : "\n## Attachments\n" + attachments.map { "- \($0.name)" }.joined(separator: "\n"))
    }
    var summaryAvailability: String? { summaryAvailability(for: .summary) }
    var automaticQuickAvailability: String? {
        if summaryProvider != nil { return nil }
        if ai.provider == .apple { return AppleIntelligenceProvider.automaticQuickUnavailableReason }
        return summaryAvailability(for: .quick)
    }
    func summaryAvailability(for mode: MobileSummaryMode) -> String? {
        if summaryProvider != nil || onDeviceProviderOverride != nil { return nil }
        if ai.provider == .ollama { return ai.availability(for: mode) }
        switch SystemLanguageModel.default.availability {
        case .available:
            // The *conversation's* language, not the device's: an unsupported one fails only at
            // generation time, so it is reported here instead of as a raw FoundationModels error.
            return AppleIntelligenceProvider.unsupportedLocaleReason(for: Locale(identifier: language))
        case .unavailable(.deviceNotEligible): return "On-device summaries require an Apple Intelligence capable device."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use on-device summaries."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence’s on-device model is not ready. Check setup in Settings → Apple Intelligence & Siri."
        default: return "On-device summaries are unavailable on this device."
        }
    }

    /// The recorder stamps "Microphone" as the display label for the local speaker. That is a device,
    /// not a participant, and the review prompts are told never to invent names, so prompt text uses
    /// the same "You" label macOS uses. The Markdown export keeps "Microphone".
    static func promptSegment(_ segment: TranscriptSegment) -> TranscriptSegment {
        guard segment.speakerName == "Microphone" else { return segment }
        var renamed = segment
        renamed.speakerName = nil
        return renamed
    }

    /// Every line carries its speaker label and typed notes are marked, so summaries never have to
    /// guess who said what. See docs/SHARED-LIVE-SUMMARY.md for the shared rule.
    var summarySource: String {
        ([MobileQuickContext.attributedNotes(notes)]
            + allSegments.map { MobileQuickContext.attributed(Self.promptSegment($0)) })
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func summaryBlockReason(for mode: MobileSummaryMode) -> String? {
        Self.summaryBlockReason(state: state, generating: isSummarizing, source: summarySource,
                                providerReason: summaryAvailability(for: mode))
    }

    static func summaryBlockReason(state: State, generating: Bool, source: String, providerReason: String?) -> String? {
        if generating { return "Generating an AI response. Wait for it to finish or tap Cancel summary." }
        if state == .preparing || state == .stopping { return "Wait for microphone setup or stopping to finish." }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add notes or wait for transcript text before generating a summary."
        }
        return providerReason
    }

    func recheckSummary(for mode: MobileSummaryMode) {
        message = summaryBlockReason(for: mode) ?? "Ready to generate \(mode.title)."
    }

    func start() {
        guard state == .idle, !isSummarizing else { return }
        message = nil
        speechCorrection.cancel()
        acceptsSpeechCorrection = true
        // Keep any unfinished hypothesis from an interrupted earlier run.
        if let partial { segments.append(partial); self.partial = nil }
        state = .preparing
        let recorder = makeRecorder()
        self.recorder = recorder
        let offset = segments.map(\.end).max() ?? 0
        startTask = Task {
            do {
                try await recorder.start(locale: Locale(identifier: language)) { [weak self] segment in
                    guard let self else { return }
                    self.speechEventCount += 1
                    if segment.isFinal { self.finalizedSpeechEventCount += 1 }
                    self.lastSpeechEvent = Date()
                    let timed = TranscriptSegment(source: .you, text: segment.text, isFinal: segment.isFinal,
                                                  start: offset + segment.start, end: offset + segment.end,
                                                  speakerName: "Microphone")
                    if timed.isFinal {
                        self.segments.append(timed)
                        self.partial = nil
                        self.save(announce: false)
                        self.checkSpeech(timed)
                    } else {
                        self.partial = timed.text.isEmpty ? nil : timed
                    }
                    self.scheduleAutoQuick()
                } onFailure: { [weak self] error in
                    guard let self, self.state == .recording || self.state == .preparing else { return }
                    self.message = error
                    Task { await self.stop() }
                }
                try Task.checkCancellation()
                state = .recording
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                try? await recorder.stop()
                self.recorder = nil
                state = .idle
                if !(error is CancellationError) { message = error.localizedDescription }
                save(announce: false)
            }
            startTask = nil
        }
    }

    func stop() async {
        guard state == .recording else {
            if state == .preparing { startTask?.cancel(); await startTask?.value }
            return
        }
        state = .stopping
        do { try await recorder?.stop() } catch { message = "Could not finalize transcript: \(error.localizedDescription)" }
        recorder = nil
        UIApplication.shared.isIdleTimerDisabled = false
        state = .idle
        save(announce: false)
    }

    func background() async {
        acceptsSpeechCorrection = false
        speechCorrection.cancel()
        summaryTask?.cancel()
        quickReader.cancel()
        let token = UIApplication.shared.beginBackgroundTask(withName: "Save conversation")
        defer { if token != .invalid { UIApplication.shared.endBackgroundTask(token) } }
        await stop()
        save(announce: false)
    }

    @discardableResult
    func save(announce: Bool = true) -> Bool {
        let record = SessionRecord(id: id, title: title, date: date,
                                   transcript: allSegments.map { "Microphone: \($0.text)" }.joined(separator: "\n"),
                                   summary: summary, segments: allSegments, notes: notes,
                                   quickSuggestion: quickSummary, deepAnswer: deepThought,
                                   isComplete: state == .idle && allSegments.allSatisfy(\.isFinal),
                                   attachments: attachments, sourceImportID: sourceImportID)
        do {
            if hasContent || history.contains(where: { $0.id == id }) { try archive.save(record) }
            try FileManager.default.createDirectory(at: activeURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: activeURL, options: .atomic)
            refreshHistory()
            if announce { message = "Conversation saved on this device." }
            return true
        } catch {
            message = "Could not save conversation: \(error.localizedDescription). Your text is still here; try Save again."
            return false
        }
    }

    func newConversation() {
        guard !busy, save(announce: false) else { return }
        speechCorrection.cancel()
        acceptsSpeechCorrection = false
        manualQuickError = nil; quickReader.reset()
        handleSummaryEvent(.conversationChanged)
        id = UUID().uuidString; date = Date()
        title = "New conversation"; notes = ""; summary = ""; quickSummary = ""; deepThought = ""
        segments = []; partial = nil; message = nil; attachments = []; sourceImportID = nil
        save(announce: false)
    }

    func open(_ record: SessionRecord) {
        guard !busy, save(announce: false) else { return }
        restore(record)
        save(announce: false)
    }

    func deleteConversation(id targetID: String) {
        guard !busy else { return }
        let deletingActive = targetID == id
        var committed = false
        do {
            // Persist an empty active snapshot first so a deleted session cannot return on relaunch.
            let empty = SessionRecord(id: UUID().uuidString, title: "New conversation", date: Date(),
                                      transcript: "", summary: "", segments: [], notes: "")
            if deletingActive {
                try FileManager.default.createDirectory(at: activeURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(empty).write(to: activeURL, options: .atomic)
            }
            try archive.delete(id: targetID)
            committed = true
            if deletingActive { restore(empty) }
            refreshHistory()
            let files = attachmentStore(for: targetID).directory
            if FileManager.default.fileExists(atPath: files.path) { try FileManager.default.removeItem(at: files) }
            let presentations = attachmentPresentationDirectory(for: targetID)
            if FileManager.default.fileExists(atPath: presentations.path) { try FileManager.default.removeItem(at: presentations) }
            message = "Conversation and attachments deleted from this device."
        } catch {
            if deletingActive && !committed { save(announce: false) }
            message = "Could not delete conversation: \(error.localizedDescription)"
        }
    }

    private func restore(_ record: SessionRecord) {
        speechCorrection.cancel()
        acceptsSpeechCorrection = false
        manualQuickError = nil; quickReader.reset()
        handleSummaryEvent(.conversationChanged)
        id = record.id; date = record.date; title = record.title
        notes = record.notes ?? ""; summary = record.summary
        quickSummary = record.quickSuggestion ?? ""; deepThought = record.deepAnswer ?? ""
        attachments = record.attachments ?? []; sourceImportID = record.sourceImportID
        segments = record.segments ?? []; partial = nil; message = nil
    }

    func importSharedInbox(from inbox: URL? = nil) {
        guard !busy else { return }
        do {
            let root = try inbox ?? SharedInbox.root()
            for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                let manifest = folder.appendingPathComponent("manifest.json")
                guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
                guard (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 2 * 1024 * 1024 else {
                    throw CocoaError(.fileReadTooLarge)
                }
                let batch = try JSONDecoder().decode(SharedImport.self, from: Data(contentsOf: manifest))
                if history.contains(where: { $0.sourceImportID == batch.id }) {
                    try FileManager.default.removeItem(at: folder); continue
                }
                guard save(announce: false) else { return }
                let newID = UUID().uuidString
                let store = attachmentStore(for: newID)
                var imported: [SessionAttachment] = []
                var committed = false
                do {
                    guard batch.files.count <= 20, batch.text.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
                    for file in batch.files {
                        guard !file.storedName.contains("/"), !file.storedName.contains("\\"),
                              file.storedName != "..", file.storedName != "." else { throw CocoaError(.fileReadInvalidFileName) }
                        let url = folder.appendingPathComponent(file.storedName)
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max)
                                <= SessionAttachmentStore.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                        let data = try Data(contentsOf: url)
                        imported.append(try store.add(data: data, name: file.name))
                    }
                    let record = SessionRecord(id: newID, title: "Imported notes", date: Date(), transcript: "",
                                               summary: "", segments: [], notes: batch.text,
                                               attachments: imported, sourceImportID: batch.id)
                    try archive.save(record)
                    committed = true
                    restore(record)
                    guard save(announce: false) else { return }
                    try FileManager.default.removeItem(at: folder)
                    message = "Shared content imported into a new conversation."
                } catch {
                    if !committed { try? FileManager.default.removeItem(at: store.directory) }
                    throw error
                }
            }
        } catch { message = "Could not import shared content: \(error.localizedDescription)" }
    }

    private func refreshHistory() {
        do { history = try archive.all() } catch { message = "Could not load history: \(error.localizedDescription)" }
    }

    func output(for mode: MobileSummaryMode) -> String {
        switch mode {
        case .summary: return summary
        case .quick: return quickSummary
        case .deep: return deepThought
        }
    }

}

extension MobileSession {
    func requestSummary(for mode: MobileSummaryMode = .summary) {
        guard summaryTask == nil else { return }
        if let reason = summaryBlockReason(for: mode) { message = reason; return }
        if mode == .quick { handleSummaryEvent(.manualQuickStarted); quickReader.clearError() }
        summaryTask = Task {
            await summarize(mode: mode)
            summaryTask = nil
            // New speech can arrive during any request. Resume at the remaining cooldown,
            // instead of adding another full interval after the response finishes.
            handleSummaryEvent(.manualQuickFinished)
        }
    }

    func scheduleAutoQuick() { handleSummaryEvent(.transcriptChanged) }

    private func handleSummaryEvent(_ event: MobileSummaryScheduler.Event) {
        if event == .conversationChanged || event == .providerChanged { automaticReviews.reset() }
        synchronizeAutomaticReviews()
        if event == .automationChanged || event == .providerChanged,
           !quickReader.context.hasChanges(quickPieces), !quickReader.isCatchingUp {
            automaticReviews.offer(quickReader.recommendations, source: summarySource)
        }
        if event == .timerFired { quickWakeCount += 1 }
        let snapshot = MobileSummaryScheduler.Snapshot(recording: state == .recording, automatic: autoQuick,
            pending: quickReader.context.hasChanges(quickPieces), reading: quickReader.isReading,
            manualQuick: generatingMode == .quick, available: automaticQuickAvailability == nil,
            correctingSpeech: speechCorrection.working, failures: quickReader.failures)
        for action in quickScheduler.plan(event, state: snapshot) {
            switch action {
            case .cancelWake: autoTask?.cancel(); autoTask = nil
            case .cancelEvaluation: quickReader.cancel()
            case .schedule(let delay):
                autoTask = Task { [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    self?.handleSummaryEvent(.timerFired)
                }
            case .evaluate:
                Task { [weak self] in await self?.updateQuickAutomatically() }
            }
        }
    }

    private var quickPieces: [MobileQuickContext.Piece] {
        MobileQuickContext.pieces(notes: notes, segments: segments.map(Self.promptSegment),
                                  liveSegments: partial.map { [Self.promptSegment($0)] } ?? [])
    }

    func updateQuickAutomatically() async {
        guard autoQuick, state == .recording, !quickReader.isReading, generatingMode != .quick else { return }
        guard automaticQuickAvailability == nil else { return }
        defer { handleSummaryEvent(.evaluationFinished) }
        if quickPieces.isEmpty {
            quickReader.reset()
            if !quickSummary.isEmpty { quickSummary = ""; save(announce: false) }
            return
        }
        do {
            guard let batch = try quickReader.context.batch(quickPieces, summary: quickSummary,
                reviewsCompleted: quickReader.reviewsCompleted, pendingReviews: quickReader.recommendations) else { return }
            let provider: any LLMProvider
            if let summaryProvider { provider = summaryProvider }
            else { provider = try ai.client(for: .quick) }
            manualQuickError = nil
            let sessionID = id
            quickEvaluationCount += 1
            let previousReads = quickReader.completedReads
            await quickReader.read(batch, provider: provider, isCurrent: { [weak self] in
                guard let self, self.id == sessionID, self.autoQuick, self.state == .recording else { return false }
                return self.quickReader.context.isCurrent(batch, pieces: self.quickPieces)
            }, apply: { [weak self] output in
                guard let self else { return }
                if self.quickSummary != output { self.quickSummary = output; self.save(announce: false) }
            })
            if quickReader.completedReads > previousReads, !quickReader.isCatchingUp {
                synchronizeAutomaticReviews()
                automaticReviews.offer(quickReader.recommendations, source: summarySource)
            }
        } catch {
            manualQuickError = "Quick Summary check failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept."
        }
    }

    private func synchronizeAutomaticReviews() {
        automaticReviews.synchronize(enabled: autoQuick && state == .recording && automaticQuickAvailability == nil,
            manualBusy: isSummarizing, source: summarySource, provider: { [weak self] mode in
                guard let self, let mobileMode = MobileSummaryMode(rawValue: mode.rawValue) else { throw CancellationError() }
                if let reason = self.summaryAvailability(for: mobileMode) { throw QuickSummaryError.message(reason) }
                return try self.summaryProvider ?? self.ai.client(for: mobileMode)
            }, apply: { [weak self] mode, output, source in
                guard let self else { return }
                if mode == .summary { self.summary = output } else { self.deepThought = output }
                if AutomaticReviewCoordinator.normalized(self.summarySource) == source {
                    self.quickReader.markReviewed(mode.rawValue)
                }
                self.save(announce: false)
            })
    }

    func automaticReviewStatus(_ mode: MobileSummaryMode) -> String {
        guard autoQuick else { return "Auto off · Generate manually." }
        guard state == .recording else { return "Auto reviews run while listening. Generate is also available." }
        if let reason = automaticQuickAvailability { return "Auto paused · " + reason }
        guard let reviewMode = AutomaticReviewMode(rawValue: mode.rawValue) else { return autoQuickStatus }
        return automaticReviews.status(reviewMode)
    }

    func cancelSummary() { summaryTask?.cancel() }

    var autoQuickStatus: String {
        guard autoQuick else { return "Auto off · Turn on Auto for live updates, or tap Refresh." }
        if generatingMode == .quick { return "Updating Quick Summary…" }
        if state != .recording {
            if quickReader.completedReads > 0, quickSummary.isEmpty, !quickReader.context.hasChanges(quickPieces) {
                return "Speech checked · No takeaway yet. Start listening to continue."
            }
            return "Auto on · Checks new speech while you listen."
        }
        if quickReader.isReading {
            return quickReader.isCatchingUp ? "Catching up · Recap covers speech processed so far." : "Listening · Checking new speech…"
        }
        if let reason = automaticQuickAvailability { return "Auto paused · " + reason }
        if quickSummaryError != nil { return "Auto on · Check failed; retrying automatically." }
        if quickReader.isCatchingUp { return "Catching up · Recap covers speech processed so far." }
        if !quickReader.context.hasChanges(quickPieces) {
            if quickReader.completedReads == 0 { return "Auto on · Waiting for more speech." }
            if quickSummary.isEmpty { return "Speech checked · No takeaway yet." }
            return quickReader.unchanged ? "Up to date · Summary unchanged." : "Up to date · Listening for new information."
        }
        return "Auto on · New speech is waiting for the next check."
    }

    func summarize(mode: MobileSummaryMode = .summary) async {
        if let reason = summaryBlockReason(for: mode) { message = reason; return }
        // Capture a stable input snapshot; recording can continue while this request runs.
        let source = summarySource
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Add notes or record a transcript before summarizing."
            return
        }
        let cloud = summaryProvider != nil || ai.provider == .ollama
        // The on-device Apple path shares its character cap with macOS (PromptBudget).
        guard source.count <= (cloud ? 60_000 : PromptBudget.appleIntelligenceCharacters) else {
            message = "This conversation exceeds the selected provider's summary limit. Export it or shorten your notes."
            return
        }
        generatingMode = mode
        isSummarizing = true
        if mode == .quick { manualQuickError = nil; quickReader.clearError() }
        message = nil
        summaryDraft = ""
        defer { isSummarizing = false; summaryDraft = ""; generatingMode = nil }
        do {
            // Apple Intelligence's on-device model cannot be held to the evaluator's JSON envelope,
            // so manual Quick asks it for the bullets directly. See docs/IOS.md → Apple Intelligence.
            let proseQuick = mode == .quick && !cloud
            let request: LLMRequest
            switch mode {
            case .quick where proseQuick:
                request = LLMRequest(system: MobileQuickContext.manualProseInstructions,
                                     messages: [ChatMessage(role: "user", content: source)])
            case .quick: request = try MobileQuickContext.manualRequest(source: source)
            default: request = LLMRequest(system: mode.instructions,
                                          messages: [ChatMessage(role: "user", content: source)])
            }
            var quickResponse = ""
            // One transport per provider: the Apple path streams through AppleIntelligenceProvider,
            // which maps FoundationModels generation failures to messages a user can act on.
            let client: any LLMProvider = try summaryProvider
                ?? (cloud ? ai.client(for: mode) : (onDeviceProviderOverride ?? AppleIntelligenceProvider()))
            for try await delta in client.stream(request) {
                try Task.checkCancellation()
                if mode == .quick { quickResponse += delta } else { summaryDraft += delta }
                guard summaryDraft.count <= 100_000, quickResponse.utf8.count <= 16_384 else {
                    throw RecordingError.message("Summary response was too large.")
                }
            }
            try Task.checkCancellation()
            switch mode {
            case .summary: summary = summaryDraft
            case .quick:
                quickSummary = (proseQuick ? MobileQuickContext.proseSummary(quickResponse)
                    : try QuickSummaryDecision.parse(quickResponse).summary) ?? "No key takeaway yet."
            case .deep: deepThought = summaryDraft
            }
            if let reviewMode = AutomaticReviewMode(rawValue: mode.rawValue) {
                automaticReviews.markManualCompletion(reviewMode, source: source)
            }
            if summarySource == source { quickReader.markReviewed(mode.rawValue) }
            save(announce: false)
        } catch {
            let failure = "\(mode.title) failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept."
            message = failure
            if mode == .quick { manualQuickError = failure }
        }
    }
}
