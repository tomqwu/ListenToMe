import AVFoundation
import Foundation
import FoundationModels
import ListenToMeCore
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class MobileSession {
    enum State { case idle, preparing, recording, stopping }
    /// Why capture last ended. `.interruption` is the only reason the system may resume from.
    enum StopReason: Equatable { case user, interruption, routeLost, background }
    var state = State.idle { didSet { handleSummaryEvent(.recordingChanged) } }
    private(set) var stopReason: StopReason?
    private(set) var isForeground = true
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
    /// A damaged history file that the archive set aside. Kept apart from `message`, which every
    /// save, restore and delete overwrites — the user must still see this when History opens.
    var archiveWarning: String?
    var isSummarizing = false { didSet { synchronizeAutomaticReviews() } }
    let ai = MobileAISettings()
    var summaryDraft = ""
    private var summaryTask: Task<Void, Never>?
    /// The transcription language survives relaunch: a user who records in Mandarin on an en_US
    /// phone should not silently fall back to the English model after every app restart.
    static let languageKey = "mobileTranscriptionLanguage"
    var language = UserDefaults.standard.string(forKey: MobileSession.languageKey) ?? Locale.current.identifier {
        didSet { UserDefaults.standard.set(language, forKey: MobileSession.languageKey) }
    }
    private(set) var id = UUID().uuidString
    private var date = Date()
    private var recorder: (any MobileRecording)?
    private var startTask: Task<Void, Never>?
    private let archive: SessionArchive
    private let activeURL: URL
    /// The bytes last written for this conversation. Identical bytes are not written again.
    private var lastSavedData: Data?
    private let saveDebounce: Duration
    private var pendingSave: Task<Void, Never>?
    /// Capture rebuilds are coalesced: several notifications describe one physical device change.
    static let captureRebuildWindow = Duration.milliseconds(500)
    private var lastCaptureRebuild: ContinuousClock.Instant?
    private var isRebuildingCapture = false
    let attachmentRoot: URL
    private let conversationRoot: URL
    /// The App Group folder the share extension writes into, when this device has one.
    let sharedInboxRoot: URL?
    /// Off by default: iOS backs app data up like any other app, and a user who relies on iCloud
    /// Backup to move to a new phone should not silently lose their conversations. On means the
    /// transcripts never leave the device, not even into an Apple-held backup.
    static let excludeBackupKey = "mobileExcludeConversationsFromBackup"
    var excludeFromBackup = UserDefaults.standard.bool(forKey: MobileSession.excludeBackupKey) {
        didSet {
            UserDefaults.standard.set(excludeFromBackup, forKey: MobileSession.excludeBackupKey)
            applyBackupExclusion()
        }
    }

    init(storageDirectory: URL = .applicationSupportDirectory,
         summaryProvider: (any LLMProvider)? = nil, autoInterval: Duration = .seconds(5),
         correctionProvider: (any LLMProvider)? = nil, saveDebounce: Duration = .seconds(1),
         sharedInbox: URL? = nil,
         makeRecorder: @escaping () -> any MobileRecording = { MobileRecorder() }) {
        // Resolved once: the backup choice has to reach the App Group inbox too, not only the
        // conversations this app owns.
        sharedInboxRoot = sharedInbox ?? (try? SharedInbox.root())
        self.summaryProvider = summaryProvider
        self.saveDebounce = saveDebounce
        self.correctionProvider = correctionProvider
        quickScheduler = MobileSummaryScheduler(interval: autoInterval)
        self.makeRecorder = makeRecorder
        activeURL = storageDirectory.appendingPathComponent("ActiveConversation.json")
        attachmentRoot = storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        conversationRoot = storageDirectory.appendingPathComponent("Conversations", isDirectory: true)
        archive = SessionArchive(directory: conversationRoot)
        refreshHistory()
        applyBackupExclusion()
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
        stopReason = nil
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
        if stopReason == nil { stopReason = .user }
        do { try await recorder?.stop() } catch { message = "Could not finalize transcript: \(error.localizedDescription)" }
        recorder = nil
        UIApplication.shared.isIdleTimerDisabled = false
        state = .idle
        save(announce: false)
    }

    func background() async {
        acceptsSpeechCorrection = false
        flushPendingSave()
        speechCorrection.cancel()
        summaryTask?.cancel()
        quickReader.cancel()
        let token = UIApplication.shared.beginBackgroundTask(withName: "Save conversation")
        defer { if token != .invalid { UIApplication.shared.endBackgroundTask(token) } }
        await stop()
        save(announce: false)
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
        pendingSave?.cancel(); pendingSave = nil
        lastSavedData = nil
        let deletingActive = targetID == id
        var committed = false
        do {
            // Persist an empty active snapshot first so a deleted session cannot return on relaunch.
            let empty = SessionRecord(id: UUID().uuidString, title: "New conversation", date: Date(),
                                      transcript: "", summary: "", segments: [], notes: "")
            if deletingActive {
                try PrivateStorage.createDirectory(at: activeURL.deletingLastPathComponent())
                try JSONEncoder().encode(empty).write(to: activeURL, options: PrivateStorage.writingOptions)
                try? PrivateStorage.setExcludedFromBackup(excludeFromBackup, at: activeURL)
            }
            try archive.delete(id: targetID)
            committed = true
            if deletingActive { restore(empty) }
            refreshHistory()
            let files = attachmentStore(for: targetID).directory
            if FileManager.default.fileExists(atPath: files.path) { try FileManager.default.removeItem(at: files) }
            let presentations = attachmentPresentationDirectory(for: targetID)
            if FileManager.default.fileExists(atPath: presentations.path) { try FileManager.default.removeItem(at: presentations) }
            archiveWarning = nil   // the user has acted on History; the note has served its purpose
            message = "Conversation and attachments deleted from this device."
        } catch {
            if deletingActive && !committed { save(announce: false) }
            message = "Could not delete conversation: \(error.localizedDescription)"
        }
    }

    private func restore(_ record: SessionRecord) {
        pendingSave?.cancel(); pendingSave = nil
        lastSavedData = nil
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


    private func refreshHistory() {
        do {
            // One undecodable file is set aside by the archive and reported; the rest still list.
            let result = try archive.read()
            history = result.records
            // Sticky for the app run: the file is renamed by the first scan, so every later scan is
            // clean. Overwriting with nil here would erase a launch-time note before History opens.
            if let warning = result.warning { archiveWarning = warning }
        } catch { message = "Could not load history: \(error.localizedDescription)" }
    }

    /// Re-reads the archive so History shows what is on disk now, including a file that became
    /// unreadable since launch. Called when the History sheet appears.
    func reloadHistory() { refreshHistory() }

    /// The user has seen the note about a set-aside file and dismissed it.
    func dismissArchiveWarning() { archiveWarning = nil }

    /// Applies the current backup choice to everything a conversation is made of. Re-applied after
    /// each toggle and at launch, because a directory recreated later starts without the flag.
    func applyBackupExclusion() {
        let excluded = excludeFromBackup
        for directory in [conversationRoot, attachmentRoot] {
            try? PrivateStorage.createDirectory(at: directory)
            try? PrivateStorage.setExcludedFromBackup(excluded, at: directory)
        }
        try? PrivateStorage.createDirectory(at: activeURL.deletingLastPathComponent())
        try? PrivateStorage.setExcludedFromBackup(excluded, at: activeURL)
        // Shared imports are conversation content that has not been imported yet; excluding only
        // what this app already owns would leave the queue in the backup the setting promises to
        // keep it out of.
        if let sharedInboxRoot {
            try? PrivateStorage.createDirectory(at: sharedInboxRoot)
            try? PrivateStorage.setExcludedFromBackup(excluded, at: sharedInboxRoot)
        }
    }

    /// Extra transcription languages offered beside the device's own.
    static let offeredLanguages = ["en-US", "en-GB", "zh-CN", "zh-TW", "fr-FR", "de-DE", "ja-JP", "es-ES"]

    /// `Locale.current.identifier` is underscored ("en_US") while these tags are hyphenated, so a
    /// raw string comparison never matched and the picker listed the system language twice.
    static func selectableLanguages(system: Locale = .current) -> [String] {
        let current = Locale(identifier: system.identifier).identifier(.bcp47)
        return offeredLanguages.filter { Locale(identifier: $0).identifier(.bcp47) != current }
    }

    /// Records matching `query`, newest first; an empty query is the full history.
    func historyMatching(_ query: String) -> [SessionRecord] {
        SessionSearch.search(history, query: query.trimmingCharacters(in: .whitespacesAndNewlines))
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
            manualBusy: isSummarizing, pieces: quickPieces, source: summarySource,
            provider: { [weak self] mode in
                guard let self, let mobileMode = MobileSummaryMode(rawValue: mode.rawValue) else { throw CancellationError() }
                if let reason = self.summaryAvailability(for: mobileMode) { throw QuickSummaryError.message(reason) }
                return try self.summaryProvider ?? self.ai.client(for: mobileMode)
            }, apply: { [weak self] mode, output, reviewed in
                guard let self else { return }
                if mode == .summary { self.summary = output } else { self.deepThought = output }
                // Same rule that kept the review alive: a notes keystroke or appended speech does not
                // make the finished review stale, so it must not leave the recommendation outstanding
                // and re-run the identical model call.
                if MobileQuickContext.isContinuation(of: reviewed, in: self.quickPieces) {
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
        let reviewed = quickPieces
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
            if MobileQuickContext.isContinuation(of: reviewed, in: quickPieces) {
                quickReader.markReviewed(mode.rawValue)
            }
            save(announce: false)
        } catch {
            let failure = "\(mode.title) failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept."
            message = failure
            if mode == .quick { manualQuickError = failure }
        }
    }
}

/// Local persistence. Saving used to re-decode the whole archive and run on every keystroke.
extension MobileSession {
    /// Persist after a quiet period instead of on every keystroke. Typing a note used to encode and
    /// fsync the whole record twice and re-decode the entire archive for each character.
    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: self.saveDebounce) } catch { return }
            guard !Task.isCancelled else { return }
            self.pendingSave = nil
            self.save(announce: false)
        }
    }

    /// Write a debounced edit immediately — before stopping, backgrounding or leaving the record.
    func flushPendingSave() {
        guard pendingSave != nil else { return }
        save(announce: false)
    }

    @discardableResult
    func save(announce: Bool = true) -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        let record = SessionRecord(id: id, title: title, date: date,
                                   transcript: allSegments.map { "Microphone: \($0.text)" }.joined(separator: "\n"),
                                   summary: summary, segments: allSegments, notes: notes,
                                   quickSuggestion: quickSummary, deepAnswer: deepThought,
                                   isComplete: state == .idle && allSegments.allSatisfy(\.isFinal),
                                   attachments: attachments, sourceImportID: sourceImportID)
        do {
            let data = try JSONEncoder().encode(record)
            guard data != lastSavedData else {
                if announce { message = "Conversation saved on this device." }
                return true
            }
            if hasContent || history.contains(where: { $0.id == id }) {
                try archive.save(record)
                remember(record)
            }
            try PrivateStorage.createDirectory(at: activeURL.deletingLastPathComponent())
            try data.write(to: activeURL, options: PrivateStorage.writingOptions)
            try? PrivateStorage.setExcludedFromBackup(excludeFromBackup, at: activeURL)
            lastSavedData = data
            if announce { message = "Conversation saved on this device." }
            return true
        } catch {
            message = "Could not save conversation: \(error.localizedDescription). Your text is still here; try Save again."
            return false
        }
    }

    /// History is kept in memory. Re-reading and decoding every conversation file on each save made
    /// typing and live transcription cost O(total archive size).
    private func remember(_ record: SessionRecord) {
        if let index = history.firstIndex(where: { $0.id == record.id }) { history[index] = record }
        else { history.append(record) }
        history.sort { $0.date > $1.date }
    }
}


/// The share-extension inbox drain. Kept out of the class body so one unreadable batch's
/// recovery path does not crowd the conversation state it operates on.
extension MobileSession {
    /// Folders set aside because they could not be imported. Recoverable from the app container for
    /// a day, then deleted: quarantined bytes the user cannot see must not be kept forever.
    static let failedInboxFolder = "Failed"
    /// A share sheet killed mid-write leaves payload files with no manifest; they can never become a
    /// conversation. Reclaimed once the extension cannot plausibly still be writing them. The same
    /// clock ages out quarantined batches.
    static let orphanInboxLifetime: TimeInterval = 24 * 60 * 60

    /// Saving the open conversation failed, so importing would lose the user's current work. Not the
    /// shared folder's fault: it stays where it is and the whole drain stops.
    private struct ActiveSaveFailure: Error { }

    /// Drains every pending share. One unreadable batch no longer blocks the rest: it is moved to
    /// `Inbox/Failed` and the drain continues, so a folder later in directory order still imports.
    func importSharedInbox(from inbox: URL? = nil, now: Date = Date()) {
        guard !busy else { return }
        var quarantined: [String] = []
        var retrying: [String] = []
        var blocked: String?
        // Reported on every exit, so a failure to save the open conversation does not swallow the
        // problems found in the folders drained before it.
        defer { announceInboxProblems(quarantined: quarantined, retrying: retrying, blocked: blocked) }
        do {
            let root = try inbox ?? sharedInboxRoot ?? SharedInbox.root()
            let failed = root.appendingPathComponent(Self.failedInboxFolder, isDirectory: true)
            discardExpiredQuarantine(failed, now: now)
            // Sorted so the drain order is the same on every launch instead of directory order.
            let folders = try FileManager.default
                .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for folder in folders where folder.lastPathComponent != Self.failedInboxFolder {
                let manifest = folder.appendingPathComponent("manifest.json")
                guard FileManager.default.fileExists(atPath: manifest.path) else {
                    discardOrphanedInbox(folder, now: now); continue
                }
                do { try importSharedBatch(at: folder, manifest: manifest) }
                catch is ActiveSaveFailure {
                    blocked = message   // save() has already said exactly what went wrong
                    return
                }
                catch {
                    if Self.isTransient(error), !isExpired(folder, now: now) {
                        retrying.append(error.localizedDescription); continue
                    }
                    quarantined.append(error.localizedDescription)
                    setAsideFailedInbox(folder, in: failed)
                }
            }
        } catch { quarantined.append(error.localizedDescription) }
    }

    /// A full disk, a read-only volume or a payload iCloud has not finished materializing describes
    /// the device's state, not the batch: quarantining it would throw away a share that imports fine
    /// once the condition clears. Retried until it is a day old, then treated as permanent so a
    /// genuinely broken batch cannot fail forever.
    static func isTransient(_ error: Error) -> Bool {
        guard let cocoa = error as? CocoaError else { return false }
        return [CocoaError.Code.fileWriteOutOfSpace, .fileWriteVolumeReadOnly, .fileWriteNoPermission,
                .fileReadNoPermission, .fileReadNoSuchFile, .fileNoSuchFile].contains(cocoa.code)
    }

    private func announceInboxProblems(quarantined: [String], retrying: [String], blocked: String?) {
        var parts: [String] = []
        if let blocked { parts.append(blocked) }
        if !quarantined.isEmpty {
            parts.append("Could not import shared content: \(quarantined.joined(separator: " ")) "
                + "Those items were set aside and are deleted after 24 hours; "
                + "anything else shared was imported.")
        }
        if !retrying.isEmpty {
            parts.append("Shared content could not be imported yet: \(retrying.joined(separator: " ")) "
                + "It stays in the queue and is tried again the next time the app opens.")
        }
        guard !parts.isEmpty else { return }
        message = parts.joined(separator: " ")
    }

    private func isExpired(_ folder: URL, now: Date) -> Bool {
        guard let changed = try? folder.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return false }
        return now.timeIntervalSince(changed) > Self.orphanInboxLifetime
    }

    /// Quarantined batches are a recovery window, not storage. After a day their bytes go back.
    private func discardExpiredQuarantine(_ failed: URL, now: Date) {
        guard let folders = try? FileManager.default
            .contentsOfDirectory(at: failed, includingPropertiesForKeys: nil) else { return }
        for folder in folders where isExpired(folder, now: now) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func importSharedBatch(at folder: URL, manifest: URL) throws {
        guard (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 2 * 1024 * 1024 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let batch = try JSONDecoder().decode(SharedImport.self, from: Data(contentsOf: manifest))
        if history.contains(where: { $0.sourceImportID == batch.id }) {
            try FileManager.default.removeItem(at: folder); return
        }
        guard save(announce: false) else { throw ActiveSaveFailure() }
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
            guard save(announce: false) else { throw ActiveSaveFailure() }
            try FileManager.default.removeItem(at: folder)
            message = "Shared content imported into a new conversation."
        } catch {
            if !committed { try? FileManager.default.removeItem(at: store.directory) }
            throw error
        }
    }

    private func discardOrphanedInbox(_ folder: URL, now: Date) {
        guard isExpired(folder, now: now) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func setAsideFailedInbox(_ folder: URL, in failed: URL) {
        do {
            try FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true,
                                                    attributes: SharedInbox.directoryAttributes)
            var destination = failed.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = failed.appendingPathComponent(folder.lastPathComponent + "-" + UUID().uuidString,
                                                            isDirectory: true)
            }
            try FileManager.default.moveItem(at: folder, to: destination)
        } catch {
            // Nowhere to move it and it can never import: dropping it is better than a permanent
            // error on every foreground.
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

/// Audio-session lifecycle. These used to live in `ListenToMeIOSApp.body`, where no test could reach
/// them; they take plain values so a unit test can drive every path.
extension MobileSession {
    static func interruption(from note: Notification) -> (type: AVAudioSession.InterruptionType,
                                                          options: AVAudioSession.InterruptionOptions)? {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        let chosen = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        return (type, AVAudioSession.InterruptionOptions(rawValue: chosen))
    }

    static func routeChangeReason(from note: Notification) -> AVAudioSession.RouteChangeReason? {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return nil }
        return AVAudioSession.RouteChangeReason(rawValue: raw)
    }

    /// A declined call, Siri or an alarm used to end the meeting silently. Say what happened, and
    /// pick capture back up when the system says the interruption is over.
    func handleInterruption(_ type: AVAudioSession.InterruptionType,
                            options: AVAudioSession.InterruptionOptions = []) async {
        switch type {
        case .began:
            guard state == .recording || state == .preparing else { return }
            await stopCapture(reason: .interruption,
                              message: "Recording stopped: audio was interrupted by a call or another app. " +
                                       "Your transcript is saved; recording resumes when the interruption ends.")
        case .ended:
            guard stopReason == .interruption, state == .idle, !isSummarizing else { return }
            guard options.contains(.shouldResume), isForeground else {
                message = "Recording stopped: audio was interrupted by a call or another app. " +
                          "Your transcript is saved; tap Listen to continue."
                return
            }
            start()
            message = "Recording resumed after the interruption."
        @unknown default: return
        }
    }

    /// Connecting AirPods mid-recording changes the input sample rate and stalls the engine, and
    /// losing a headset does not mean the meeting is over: rebuild capture instead of stopping.
    func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) async {
        guard state == .recording, let recorder else { return }
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override:
            // One physical event can post several route changes (and the recorder sees an engine
            // configuration change for the same event), so rebuilds are coalesced.
            guard !isRebuildingCapture else { return }
            if let lastCaptureRebuild, ContinuousClock.now - lastCaptureRebuild < Self.captureRebuildWindow { return }
            isRebuildingCapture = true
            do {
                try await recorder.reconfigure()
                isRebuildingCapture = false
                lastCaptureRebuild = ContinuousClock.now
                message = reason == .newDeviceAvailable
                    ? "Microphone changed: recording continues on the newly connected microphone."
                    : "Microphone changed: recording continues on the available microphone."
            } catch {
                isRebuildingCapture = false
                await stopCapture(reason: .routeLost,
                                  message: "Recording stopped: the microphone changed and capture could not " +
                                           "restart (\(error.localizedDescription)). Your transcript is saved; " +
                                           "tap Listen to continue.")
            }
        default: return
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        isForeground = phase != .background
        // Suspension can follow .inactive without another chance to run, so pending typing is
        // written here as well as from the App body's synchronous forwarder.
        flushPendingSave()
        switch phase {
        case .active:
            importSharedInbox()
        case .background:
            let capturing = state == .recording || state == .preparing
            let before = message
            await background()
            if capturing {
                stopReason = .background
                if message == before {
                    message = "Recording stopped: ListenToMe moved to the background. " +
                              "Your transcript is saved; tap Listen to continue."
                }
            }
        default: return
        }
    }

    /// Stop and explain why, without overwriting a more specific failure raised while finalizing.
    private func stopCapture(reason: StopReason, message text: String) async {
        let before = message
        stopReason = reason
        await stop()
        stopReason = reason
        if message == before { message = text }
    }
}
