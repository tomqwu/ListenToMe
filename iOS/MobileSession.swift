import AVFoundation
import Foundation
import FoundationModels
import ListenToMeCore
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class MobileSession {
    typealias State = CaptureCoordinator.Phase
    /// Why capture last ended. `.interruption` is the only reason the system may resume from.
    enum StopReason: Equatable { case user, interruption, routeLost, background }
    var state = State.idle {
        didSet {
            handleSummaryEvent(.recordingChanged)
            if state == .recording, oldValue != .recording { recordingStartedAt = Date() }
            if state == .idle { recordingStartedAt = nil }
            publishWatchStatus()
        }
    }
    var stopReason: StopReason? { didSet { if stopReason != oldValue { publishWatchStatus() } } }
    private(set) var isForeground = true
    /// When the current recording run started, for the Apple Watch remote's elapsed time (issue #181).
    private(set) var recordingStartedAt: Date?
    /// Receives the recorder status for the Apple Watch; `nil` until the app attaches its link.
    @ObservationIgnored var watchLink: (any WatchLinking)?
    /// Whether the app is active in the foreground. Tests replace it; a watch Start never reaches the
    /// microphone otherwise.
    @ObservationIgnored var applicationIsActive: @MainActor () -> Bool = {
        UIApplication.shared.applicationState == .active
    }
    var title = ConversationTitle.mobileDefault
    var titleState = ConversationTitleState.placeholder   // where the title came from (#221)
    @ObservationIgnored let titleCoordinator = ConversationTitleCoordinator()
    var summaryInstructions = "" { didSet { handleSummaryEvent(.notesChanged) } }
    var notes = "" { didSet { handleSummaryEvent(.notesChanged) } }
    var summary = ""
    var quickSummary = ""
    /// Deep analysis an older version saved here; kept read-only, never generated on iOS (#235).
    var earlierDeepAnalysis = ""
    var selectionSummaries: [SelectionSummary] = []   // the last few summaries of selected lines (#234)
    let selectionRun = MobileSelectionRun()
    var attachments: [SessionAttachment] = []
    var generatingMode: MobileSummaryMode?
    var autoQuick = UserDefaults.standard.bool(forKey: "autoQuickSummary") {
        didSet { UserDefaults.standard.set(autoQuick, forKey: "autoQuickSummary"); handleSummaryEvent(.automationChanged) }
    }
    let quickReader = MobileQuickReader(); let suggestedAsk = MobileSuggestedAsk()   // chip asks: #61
    let automaticReviews = AutomaticReviewCoordinator(modes: [.summary])   // no Deep on iOS (#235)
    private(set) var speechEventCount = 0
    private(set) var finalizedSpeechEventCount = 0
    private(set) var quickWakeCount = 0
    private(set) var quickEvaluationCount = 0
    private(set) var lastSpeechEvent: Date?
    var quickDiagnostics: String {
        ([autoQuickStatus, "Recording: \(state == .recording ? "yes" : "no")",
         "Speech events: \(speechEventCount) (final: \(finalizedSpeechEventCount))",
         "Last speech: \(lastSpeechEvent?.formatted(date: .omitted, time: .standard) ?? "none")",
         "Scheduled checks fired: \(quickWakeCount)", "Model checks started: \(quickEvaluationCount)",
         "Completed reads: \(quickReader.completedReads)",
         "Unread speech: \(quickReader.context.hasChanges(quickPieces) ? "yes" : "no")",
         "Provider: \(automaticQuickAvailability ?? "available")",
         quickSummaryError ?? "No summary error"] + speakerDiagnostics + [languageDiagnostics])
            .joined(separator: "\n")
    }
    private var quickScheduler: MobileSummaryScheduler
    private var autoTask: Task<Void, Never>?
    let summaryProvider: (any LLMProvider)?
    /// The on-device transport used when the provider is Apple Intelligence. Only tests replace it,
    /// so the simulator can exercise the on-device path without an Apple Intelligence capable host.
    var onDeviceProviderOverride: (any LLMProvider)?
    let correctionProvider: (any LLMProvider)?
    let speechCorrection = MobileTranscriptCorrector()
    let vocabulary = SessionVocabulary()   // domain vocabularies and My terms (issue #222)
    var acceptsSpeechCorrection = false
    let makeRecorder: () -> any MobileRecording
    @ObservationIgnored var watchSpeakerContexts: [UUID: WatchSpeakerLabels] = [:]
    var watchLanguageSamples: ([WatchAudioChunk]) async throws -> [Float] = WatchLanguageAudio.samples
    let makeWatchTranscriber: () -> any WatchAudioTranscribing
    /// The foreground drain of Apple Watch recordings (issue #181); never runs while recording.
    @ObservationIgnored var watchDrainTask: Task<Void, Never>?
    /// Watch recordings still waiting in the inbox, for History.
    var watchInboxRows: [WatchInboxRow] = []
    /// Watch audio that could not be kept, until the user dismisses the note in History.
    var watchInboxProblems: [String] = []
    /// A chunk arrived while a drain ran; drain again when it ends.
    @ObservationIgnored var watchDrainRequested = false
    /// The Apple Watch's own recording, from its application context (Slice 3); see `receiveWatchContext`.
    var watchCaptureStatus: WatchCaptureStatus?
    var manualQuickError: String?
    var quickSummaryError: String? { manualQuickError ?? quickReader.error }
    private(set) var sourceImportID: String?
    var segments: [TranscriptSegment] = [] { didSet { liveRevision += 1; scheduleAutoQuick() } }
    var liveRevision = 0
    @ObservationIgnored var liveCacheKey: LiveKey?
    @ObservationIgnored var liveCache: LiveSnapshot?
    @ObservationIgnored var liveSnapshotComputations = 0
    var partial: TranscriptSegment?
    var history: [SessionRecord] = []
    var message: String?
    /// A damaged history file that the archive set aside. Kept apart from `message`, which every
    /// save, restore and delete overwrites — the user must still see this when History opens.
    var archiveWarning: String?
    var isSummarizing = false {
        didSet { synchronizeAutomaticReviews(); if isSummarizing != oldValue { publishWatchStatus() } }
    }
    let ai = MobileAISettings()
    var summaryDraft = ""
    var answerNotices = MobileAnswerNotices()   // Grounding and cut-off lines (issues #114, #215)
    private var summaryTask: Task<Void, Never>?
    /// The transcription language survives relaunch: a user who records in Mandarin on an en_US
    /// phone should not silently fall back to the English model after every app restart.
    static let languageKey = "mobileTranscriptionLanguage"
    var language = UserDefaults.standard.string(forKey: MobileSession.languageKey) ?? Locale.current.identifier {
        didSet { UserDefaults.standard.set(language, forKey: MobileSession.languageKey) }
    }
    private(set) var id = UUID().uuidString
    private var date = Date()
    var recorder: (any MobileRecording)?
    let captureCoordinator = CaptureCoordinator()
    /// On-device speaker identification (issues #180, #195) and its periodic pass while recording.
    let speakers: MobileSpeakers
    let languageDetection: MobileLanguageDetection   // Automatic transcription language (issue #197)
    let savedAudio: MobileSavedAudio   // Save audio recordings, off by default (issue #55)
    var speakerLoop: Task<Void, Never>?
    @ObservationIgnored var speakerSleep: @Sendable (TimeInterval) async throws -> Void = {
        try await Task.sleep(for: .seconds($0))
    }
    /// Stop's final speaker pass, which runs after the session is already idle.
    var speakerFinalPass: Task<Void, Never>?
    let archive: SessionArchive
    let activeURL: URL
    /// The bytes last written for this conversation. Identical bytes are not written again.
    var lastSavedData: Data?
    private let saveDebounce: Duration
    var pendingSave: Task<Void, Never>?
    /// Capture rebuilds are coalesced: several notifications describe one physical device change.
    static let captureRebuildWindow = Duration.milliseconds(500)
    private var lastCaptureRebuild: ContinuousClock.Instant?
    private var isRebuildingCapture = false
    let attachmentRoot: URL
    private let conversationRoot: URL
    /// The App Group folder the share extension writes into, when this device has one.
    let sharedInboxRoot: URL?
    /// Apple Watch audio waiting to be transcribed (issue #181).
    let watchInbox: WatchInbox
    /// Off by default: iOS backs app data up like any other app, and a user who relies on iCloud
    /// Backup to move to a new phone should not silently lose their conversations. On means the
    /// transcripts never leave the device, not even into an Apple-held backup.
    nonisolated static let excludeBackupKey = "mobileExcludeConversationsFromBackup"
    var excludeFromBackup = UserDefaults.standard.bool(forKey: MobileSession.excludeBackupKey) {
        didSet {
            UserDefaults.standard.set(excludeFromBackup, forKey: MobileSession.excludeBackupKey)
            applyBackupExclusion()
        }
    }

    init(storageDirectory: URL = .applicationSupportDirectory,
         summaryProvider: (any LLMProvider)? = nil, autoInterval: Duration = .seconds(5),
         correctionProvider: (any LLMProvider)? = nil, saveDebounce: Duration = .seconds(1),
         sharedInbox: URL? = nil, watchInbox: WatchInbox? = nil,
         makeRecorder: @escaping () -> any MobileRecording = { MobileRecorder() },
         makeWatchTranscriber: @escaping () -> any WatchAudioTranscribing = { MobileFileTranscriber() },
         makeDiarizer: @escaping () -> any MobileSpeakerDiarizing = MobileSpeakers.deviceDiarizer,
         makeLanguageModel: (() -> any MobileLanguageIdentifying)? = nil, savedAudio: MobileSavedAudio? = nil) {
        speakers = MobileSpeakers(makeDiarizer: makeDiarizer)
        self.savedAudio = savedAudio ?? MobileSavedAudio(root: storageDirectory.appendingPathComponent("SavedAudio"))
        languageDetection = MobileLanguageDetection(makeIdentifier: makeLanguageModel)
        // Resolved once: the backup choice has to reach the App Group inbox too, not only the
        // conversations this app owns.
        sharedInboxRoot = sharedInbox ?? (try? SharedInbox.root())
        self.summaryProvider = summaryProvider
        self.saveDebounce = saveDebounce
        self.correctionProvider = correctionProvider
        quickScheduler = MobileSummaryScheduler(interval: autoInterval)
        self.makeRecorder = makeRecorder
        self.makeWatchTranscriber = makeWatchTranscriber
        activeURL = storageDirectory.appendingPathComponent("ActiveConversation.json")
        attachmentRoot = storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        conversationRoot = storageDirectory.appendingPathComponent("Conversations", isDirectory: true)
        archive = SessionArchive(directory: conversationRoot)
        self.watchInbox = watchInbox ?? WatchInbox(root: storageDirectory.appendingPathComponent("WatchInbox"))
        refreshHistory()
        applyBackupExclusion()
        if FileManager.default.fileExists(atPath: activeURL.path) {
            do { restore(try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: activeURL))) }
            catch { message = "Could not restore the current conversation: \(error.localizedDescription). Check History." }
        } else if let latest = history.first { restore(latest) }
        ai.correctionSettingsChanged = { [weak self] in self?.speechCorrection.cancel() }
        ai.quickSettingsChanged = { [weak self] in
            guard let self else { return }
            self.suggestionsProviderChanged()
            self.handleSummaryEvent(.providerChanged)
        }
    }

    var busy: Bool { state != .idle || isSummarizing }
    var hasContent: Bool {
        !segments.isEmpty || partial != nil || !notes.isEmpty || !summaryInstructions.isEmpty || !summary.isEmpty
            || !quickSummary.isEmpty || !earlierDeepAnalysis.isEmpty || !attachments.isEmpty
    }
    var allSegments: [TranscriptSegment] { segments + (partial.map { [$0] } ?? []) }
    /// The open conversation as it is saved, and as every export formats it (#130), in its languages (#206).
    var currentRecord: SessionRecord {
        withConversationLanguages(SessionRecord(id: id, title: title, date: date,
            transcript: Self.transcriptText(for: allSegments), summary: summary, segments: allSegments, notes: notes,
            quickSuggestion: quickSummary, deepAnswer: earlierDeepAnalysis, isComplete: state == .idle
                && allSegments.allSatisfy(\.isFinal), attachments: attachments, sourceImportID: sourceImportID,
            titleState: titleState, selectionSummaries: selectionSummaries.isEmpty ? nil : selectionSummaries,
            summaryInstructions: summaryInstructions.isEmpty ? nil : summaryInstructions,
            vocabularyDomainIDs: vocabulary.domainIDs(for: id).sorted()))
    }
    var summaryAvailability: String? { summaryAvailability(for: .summary) }
    var automaticQuickAvailability: String? {
        if summaryProvider != nil { return nil }
        if ai.provider == .apple { return AppleIntelligenceProvider.automaticQuickUnavailableReason }
        return summaryAvailability(for: .quick) ?? ai.automaticQuickReason
    }
    func summaryAvailability(for mode: MobileSummaryMode) -> String? {
        if summaryProvider != nil || onDeviceProviderOverride != nil { return nil }
        if ai.provider != .apple { return ai.availability(for: mode) }
        switch SystemLanguageModel.default.availability {
        case .available:
            // The *conversation's* language, not the device's: an unsupported one fails only at
            // generation time, so it is reported here instead of as a raw FoundationModels error.
            return AppleIntelligenceProvider.unsupportedLocaleReason(for: Locale(identifier: conversationLanguage))
        case .unavailable(.deviceNotEligible): return "On-device summaries require an Apple Intelligence capable device."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use on-device summaries."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence’s on-device model is not ready. Check setup in Settings → Apple Intelligence & Siri."
        default: return "On-device summaries are unavailable on this device."
        }
    }

    /// "Microphone" (and "Apple Watch" on a watch recording's lines) names a device, not a participant,
    /// and the review prompts are told never to invent names, so prompt text uses the "You" label macOS
    /// uses; the Markdown export keeps the device label. Lines that speaker identification labeled
    /// ("Speaker 2", or the name the user gave) reach prompts unchanged.
    static func promptSegment(_ segment: TranscriptSegment) -> TranscriptSegment {
        guard isDeviceLabel(segment.speakerName) else { return segment }
        var renamed = segment
        renamed.speakerName = nil
        return renamed
    }

    /// Every line carries its speaker label and typed notes are marked, so summaries never have to
    /// guess who said what. See docs/SHARED-LIVE-SUMMARY.md for the shared rule.
    var summarySource: String { liveSnapshot().source }

    func summaryBlockReason(for mode: MobileSummaryMode) -> String? {
        Self.summaryBlockReason(state: state, generating: isSummarizing, source: liveSnapshot().manualSource,
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

    func background() async {
        cancelSpeakerIdentification()
        acceptsSpeechCorrection = false
        flushPendingSave()
        speechCorrection.cancel()
        cancelSummary()   // the manual request and any selection summary (#234)
        quickReader.cancel()
        let token = UIApplication.shared.beginBackgroundTask(withName: "Save conversation")
        defer { if token != .invalid { UIApplication.shared.endBackgroundTask(token) } }
        watchDrainTask?.cancel()
        await watchDrainTask?.value
        await stop()
        save(announce: false)
    }

    func newConversation() {
        guard !busy, save(announce: false) else { return }
        speechCorrection.cancel()
        acceptsSpeechCorrection = false
        manualQuickError = nil; resetSuggestions(); answerNotices = MobileAnswerNotices()
        handleSummaryEvent(.conversationChanged)
        id = UUID().uuidString; date = Date()
        vocabulary.restore(domainIDs: nil, for: id)
        title = ConversationTitle.mobileDefault; titleState = .placeholder; notes = ""; summaryInstructions = ""; summary = ""
        quickSummary = ""; earlierDeepAnalysis = ""; selectionSummaries = []
        segments = []; partial = nil; message = nil; attachments = []; sourceImportID = nil
        save(announce: false)
    }

    func open(_ record: SessionRecord) {   // History's current copy, never a deleted or stale one
        guard !busy, history.contains(where: { $0.id == record.id }), save(announce: false) else { return }
        restore(history.first { $0.id == record.id } ?? record)
        save(announce: false)
    }

    func restore(_ record: SessionRecord) {
        pendingSave?.cancel(); pendingSave = nil
        lastSavedData = nil
        speechCorrection.cancel()
        acceptsSpeechCorrection = false
        manualQuickError = nil; resetSuggestions(); answerNotices = MobileAnswerNotices()
        handleSummaryEvent(.conversationChanged)
        id = record.id; date = record.date; title = record.title; titleState = record.resolvedTitleState
        vocabulary.restore(domainIDs: record.vocabularyDomainIDs, for: id)
        notes = record.notes ?? ""; summaryInstructions = record.summaryInstructions ?? ""; summary = record.summary
        quickSummary = record.quickSuggestion ?? ""; earlierDeepAnalysis = record.deepAnswer ?? ""
        selectionSummaries = record.selectionSummaries ?? []
        attachments = record.attachments ?? []; sourceImportID = record.sourceImportID
        segments = record.segments ?? []; partial = nil; message = nil
    }

    private func refreshHistory() {
        do {
            // One undecodable file is set aside by the archive and reported; the rest still list.
            let result = try archive.read()
            history = result.records; indexHistory()
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

}

// Storage policy is independent of capture lifecycle.
extension MobileSession {
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
        // Raw watch audio is always kept out of the backup, whatever this setting says.
        watchInbox.applyBackupExclusion()
    }
}

/// Outputs: plain lookups, kept out of the class body. Search is in MobileSession+HistorySearch.
extension MobileSession {
    func output(for mode: MobileSummaryMode) -> String {
        switch mode {
        case .summary: return summary
        case .quick: return quickSummary
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
        let live = liveSnapshot()
        synchronizeAutomaticReviews(live)
        if event == .automationChanged || event == .providerChanged,
           !quickReader.context.hasChanges(live.pieces), !quickReader.isCatchingUp {
            automaticReviews.offer(quickReader.recommendations, source: live.source)
        }
        if event == .timerFired { quickWakeCount += 1 }
        let snapshot = MobileSummaryScheduler.Snapshot(recording: state == .recording, automatic: autoQuick,
            pending: quickReader.context.hasChanges(live.pieces), reading: quickReader.isReading,
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

    var quickPieces: [MobileQuickContext.Piece] { liveSnapshot().pieces }

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
            let provider: any LLMProvider
            if let summaryProvider { provider = summaryProvider }
            else { provider = try ai.client(for: .quick) }
            let vocabularyAtStart = activeVocabulary
            let guidance = VocabularyPrompt.guidance(for: vocabularyAtStart,
                transcript: String(summarySource.suffix(4_000)),
                characterLimit: VocabularyPrompt.characterLimit(forPromptWindow: provider.maxPromptCharacters))
            guard let batch = try quickReader.context.batch(quickPieces, summary: quickSummary,
                reviewsCompleted: quickReader.reviewsCompleted, pendingReviews: quickReader.recommendations,
                summaryInstructions: summaryInstructions, personaGuidance: guidance) else { return }
            manualQuickError = nil
            let instructionsAtStart = summaryInstructions
            let sessionID = id
            quickEvaluationCount += 1
            let previousReads = quickReader.completedReads
            await quickReader.read(batch, provider: provider, isCurrent: { [weak self] in
                guard let self, self.id == sessionID, self.summaryInstructions == instructionsAtStart, self.activeVocabulary == vocabularyAtStart,
                      self.autoQuick, self.state == .recording else { return false }
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

    private func synchronizeAutomaticReviews() { synchronizeAutomaticReviews(liveSnapshot()) }

    private func synchronizeAutomaticReviews(_ live: LiveSnapshot) {
        automaticReviews.synchronize(enabled: autoQuick && state == .recording && automaticQuickAvailability == nil,
            manualBusy: isSummarizing, pieces: live.pieces, source: live.source, directives: vocabularyDirectives,
            provider: { [weak self] mode in   // Summary only: the coordinator runs no Deep on iOS (#235)
                guard let self, mode == .summary else { throw CancellationError() }
                if let reason = self.summaryAvailability(for: .summary) { throw QuickSummaryError.message(reason) }
                return try self.summaryProvider ?? self.ai.client(for: .summary)
            }, apply: { [weak self] mode, output, reviewed in
                guard let self, mode == .summary else { return }
                self.summary = output
                self.answerNotices.record(.summary, text: output, grounding: nil,
                                          cutOff: self.automaticReviews.cutOffModes.contains(mode),
                                          coveredIDs: QuickSummaryContext.segmentIDs(in: reviewed))
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

    func cancelSummary() { summaryTask?.cancel(); cancelSelectionSummary() }

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
    func flushPendingSave() { if pendingSave != nil { save(announce: false) } }

    @discardableResult
    func save(announce: Bool = true) -> Bool {
        pendingSave?.cancel(); pendingSave = nil
        let record = currentRecord
        do {
            let data = try Self.stableEncoder.encode(record)
            guard data != lastSavedData else {
                if announce { message = "Conversation saved on this device." }
                return true
            }
            if hasContent || history.contains(where: { $0.id == id }) {
                try archive.save(record)
                remember(record); exportToVault(record)
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

    static func transcriptText(for segments: [TranscriptSegment]) -> String {
        segments.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n")
    }

    /// History is kept in memory. Re-reading and decoding every conversation file on each save made
    /// typing and live transcription cost O(total archive size).
    func remember(_ record: SessionRecord) {
        if let index = history.firstIndex(where: { $0.id == record.id }) { history[index] = record }
        else { history.append(record) }
        history.sort { $0.date > $1.date }
        indexSaved(record)
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
            importSharedInbox(); importWatchInbox(); nameConversationIfNeeded()
            prepareSpeakerModelsIfNeeded()   // speaker models load in the foreground only (#195)
            // The watch may still show "Open ListenToMe…" from a Start sent while this was closed.
            publishWatchStatus()
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

// Kept beside private speech counters; capture task orchestration lives in Core.
extension MobileSession {
    func receiveCaptureSegment(_ segment: TranscriptSegment, offset: TimeInterval) {
        speechEventCount += 1
        if segment.isFinal { finalizedSpeechEventCount += 1 }
        lastSpeechEvent = Date()
        if stageLanguageSegment(segment, offset: offset) { return }
        let timed = TranscriptSegment(source: .you, text: segment.text, isFinal: segment.isFinal,
                                      start: offset + segment.start, end: offset + segment.end,
                                      speakerName: Self.microphoneLabel, language: recordingLanguage)
        if timed.isFinal {
            segments.append(timed); partial = nil
            save(announce: false); checkSpeech(timed)
        } else {
            partial = timed.text.isEmpty ? nil : timed
        }
        scheduleAutoQuick()
    }

}
