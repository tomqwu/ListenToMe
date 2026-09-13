import Foundation
import Observation

/// Orchestrates capture -> transcription -> store -> proactive/on-demand responses
/// across three independent AI pane roles (Listener, Quick, Deep).
/// Depends only on protocols, so it is fully unit-testable with mocks.
@MainActor
@Observable
public final class MeetingSession {
    public private(set) var isRunning = false
    public var notes = "" { didSet { handleLiveEvent(.notesChanged) } }
    public var proactiveEnabled = true
    public var autoSummaryEnabled = false { didSet { handleLiveEvent(.automationChanged) } }
    public var aiEnabled = true {
        didSet { if !aiEnabled { for role in CopilotRole.allCases { cancelResponse(role) } }; handleLiveEvent(.providerChanged) }
    }
    public private(set) var captureMessages: [SpeakerSource: String] = [:]
    public private(set) var transcriptionStatus = "Transcription: idle"
    public var captureStatus: String {
        "Mic: \(captureMessages[.you] ?? "idle") · System: \(captureMessages[.others] ?? "idle")"
    }
    private var captureStatusTask: Task<Void, Never>?
    private var transcriptionStatusTask: Task<Void, Never>?

    /// Forces all AI replies (Listener/Quick/Deep) into this language, e.g. "Simplified Chinese";
    /// nil/empty leaves the model free to match the conversation. Set from the UI's Settings.
    public var responseLanguage: String?
    /// Attached reference material (file/folder contents) fed into Quick/Deep prompts as grounding;
    /// nil/empty = none. Set from the UI when the user attaches files.
    public var referenceContext: String?
    /// Use-case persona guidance from the selected preset, injected into all pane prompts.
    public var personaGuidance: String?
    public let store: ConversationStore

    /// Per-role output properties
    public private(set) var listenerSummary = ""
    public private(set) var quickSuggestion = ""
    public private(set) var deepAnswer = ""

    /// The last *completed* listener summary, used as grounding for Quick/Deep prompts. Kept
    /// separate from `listenerSummary` (the live display value, which is cleared to "" while a new
    /// refresh streams) so a proactive Quick can't read an empty/partial in-flight summary.
    private var lastCompletedListenerSummary = ""
    private var summarizedSegmentIDs = Set<UUID>()
    private var pendingSummaryIDs: [Int: Set<UUID>] = [:]

    /// True while an imported audio file is being transcribed into the store.
    public private(set) var isTranscribingFile = false

    /// The set of roles currently streaming a response.
    public private(set) var streamingRoles: Set<CopilotRole> = []

    /// The model ID assigned to each role.
    public private(set) var models: [CopilotRole: String]

    public let quickReader = QuickSummaryReader()
    private var liveScheduler = LiveSummaryScheduler()
    private var liveWake: Task<Void, Never>?

    private var context: ContextEngine
    private let makeCapture: @Sendable () -> any AudioCapturing
    private let makeTranscriber: @Sendable () -> any Transcribing
    private let providerAvailability: @Sendable (String) -> String?
    private let makeProvider: @Sendable (String) -> any LLMProvider
    private var providers: [CopilotRole: any LLMProvider]
    private var capture: (any AudioCapturing)?
    private var transcriber: (any Transcribing)?
    private let clock: @Sendable () -> TimeInterval

    /// Capture -> transcriber.feed pump. Drained (awaited) BEFORE finishing the transcriber so the
    /// last buffered chunks are fed before finalization.
    private var capturePump: Task<Void, Never>?
    /// transcriber.segments -> ingest pump. Drained AFTER finishing the transcriber so every final
    /// segment is ingested into the store.
    private var segmentPump: Task<Void, Never>?
    /// In-flight transcriber teardown from the last stop. `start()` awaits it before creating a new
    /// transcriber so a quick restart can't run two transcribers at once (SFSpeechRecognizer 1100).
    private var stopDrain: Task<Void, Never>?
    private var responseTasks: [CopilotRole: Task<Void, Never>] = [:]
    private var responseGenerations: [CopilotRole: Int] = [:]
    private var runID = 0

    public init(store: ConversationStore,
                context: ContextEngine,
                makeCapture: @escaping @Sendable () -> any AudioCapturing,
                makeTranscriber: @escaping @Sendable () -> any Transcribing,
                makeProvider: @escaping @Sendable (String) -> any LLMProvider,
                models: [CopilotRole: String],
                listenerDebounce: TimeInterval = 12,
                autoInterval: Duration = .seconds(5),
                providerAvailability: @escaping @Sendable (String) -> String? = { _ in nil },
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.context = context
        self.makeCapture = makeCapture
        self.makeTranscriber = makeTranscriber
        self.providerAvailability = providerAvailability
        self.makeProvider = makeProvider
        self.models = models
        self.liveScheduler = LiveSummaryScheduler(interval: autoInterval)
        self.clock = clock
        // Build initial providers from models
        var built: [CopilotRole: any LLMProvider] = [:]
        for (role, modelID) in models {
            built[role] = makeProvider(modelID)
        }
        self.providers = built
    }

    // MARK: - Model management

    /// Changes the model for a role and rebuilds its provider.
    public func setModel(_ role: CopilotRole, _ model: String) {
        cancelResponse(role)
        models[role] = model
        providers[role] = makeProvider(model)
        if role == .quick { quickReader.clearError(); handleLiveEvent(.providerChanged) }
    }

    public func cancelResponse(_ role: CopilotRole) {
        responseTasks[role]?.cancel()
        responseGenerations[role, default: 0] += 1
        streamingRoles.remove(role)
    }

    public func resetConversation() {
        guard !isRunning, !isTranscribingFile else { return }
        for role in CopilotRole.allCases { cancelResponse(role) }
        quickReader.reset(); handleLiveEvent(.conversationChanged)
        store.reset()
        notes = ""; referenceContext = nil
        listenerSummary = ""; quickSuggestion = ""; deepAnswer = ""
        lastCompletedListenerSummary = ""
        summarizedSegmentIDs = []
        pendingSummaryIDs = [:]
        context = ContextEngine(debounce: context.debounce)
        runID += 1
    }

    // MARK: - Session lifecycle

    public func start() async throws {
        guard !isRunning, !isTranscribingFile else { return }
        isRunning = true
        handleLiveEvent(.recordingChanged)
        // Wait for any prior transcriber to finish draining BEFORE bumping runID, so the old
        // session's segment pump still ingests its final segments under its own runID (a bump here
        // would make its `guard runID == myRun` fail and drop the just-stopped session's last audio).
        // This also keeps two transcribers from running concurrently.
        await stopDrain?.value
        stopDrain = nil
        guard isRunning else { return }   // a stop() during that await cancels this start
        runID += 1
        let myRun = runID
        let capture = makeCapture()
        let transcriber = makeTranscriber()
        // Store before the await so stop() can reach an in-flight capture (whose mic may already
        // be recording) if the user stops during permission/startup.
        self.capture = capture
        self.transcriber = transcriber
        captureMessages = [.you: "starting…", .others: "starting…"]
        transcriptionStatus = "Transcription: waiting for audio"
        captureStatusTask?.cancel(); transcriptionStatusTask?.cancel()
        captureStatusTask = Task {
            for await status in capture.statusUpdates {
                guard self.runID == myRun, self.isRunning else { break }
                self.captureMessages[status.source] = status.message
            }
        }
        transcriptionStatusTask = Task {
            for await status in transcriber.statusUpdates {
                guard self.runID == myRun else { break }
                self.transcriptionStatus = status
            }
        }
        do {
            try await capture.start()
        } catch {
            capture.stop()
            if runID == myRun {
                isRunning = false
                captureStatusTask?.cancel(); transcriptionStatusTask?.cancel()
                captureMessages = [.you: "start failed", .others: "stopped"]
                transcriptionStatus = "Transcription: not started"
                self.capture = nil
                self.transcriber = nil
            }
            throw error
        }
        guard isRunning, runID == myRun else { capture.stop(); return }

        let captureStream = capture.chunks
        capturePump = Task {
            for await chunk in captureStream {
                await transcriber.feed(chunk)
            }
        }

        let segmentStream = transcriber.segments
        segmentPump = Task { [weak self] in
            for await segment in segmentStream {
                guard let self else { return }
                guard self.runID == myRun else { continue }   // ignore stale-session segments
                await self.ingest(segment)
            }
        }
    }

    public func stop() {
        guard let teardown = beginStop() else { return }
        stopDrain = Task { await Self.drain(teardown) }
    }

    /// Like `stop()`, but awaits full teardown before returning, so an immediately following
    /// `start()` cannot overlap the previous transcriber (which can trigger SFSpeechRecognizer's
    /// `kAFAssistantErrorDomain 1100` overlap error), and so callers reading `store` afterward see
    /// every final segment. Used when restarting to apply a new locale, and before saving a session.
    public func stopAndWait() async {
        guard let teardown = beginStop() else {
            await stopDrain?.value   // a prior fire-and-forget stop() may still be draining
            return
        }
        let drain = Task { await Self.drain(teardown) }
        stopDrain = drain
        await drain.value
        transcriptionStatusTask?.cancel()
        if transcriptionStatus.hasPrefix("Transcription:") { transcriptionStatus = "Transcription: stopped" }
    }

    /// Awaits full teardown in feed-before-finalize order: drain the capture pump (feed every
    /// remaining chunk), THEN finish the transcriber (finalize), THEN drain the segment pump (ingest
    /// every final into the store). This guarantees the last buffered audio isn't dropped by an
    /// early `finish()`. Static so it captures only the teardown payload, not `self`.
    private static func drain(
        _ teardown: (transcriber: (any Transcribing)?,
                     capturePump: Task<Void, Never>?,
                     segmentPump: Task<Void, Never>?)
    ) async {
        await teardown.capturePump?.value
        if let transcriber = teardown.transcriber { await transcriber.finish() }
        await teardown.segmentPump?.value
    }

    /// Shared synchronous teardown. Returns the transcriber to `finish()` and the two pumps to
    /// drain (via `drain`), or nil when nothing is running.
    private func beginStop() -> (transcriber: (any Transcribing)?,
                                 capturePump: Task<Void, Never>?,
                                 segmentPump: Task<Void, Never>?)? {
        guard isRunning else { return nil }
        isRunning = false
        handleLiveEvent(.recordingChanged)
        captureStatusTask?.cancel()
        captureMessages = [.you: "stopped", .others: "stopped"]
        transcriptionStatus = "Transcription: finalizing…"
        for role in CopilotRole.allCases { cancelResponse(role) }
        capture?.stop()
        let transcriber = self.transcriber
        let capturePump = self.capturePump
        let segmentPump = self.segmentPump
        capture = nil
        self.transcriber = nil
        self.capturePump = nil
        self.segmentPump = nil
        // Nothing installed yet (e.g. Stop while a new start() is still awaiting the previous
        // stopDrain): there's nothing to tear down, so return nil and leave the in-flight stopDrain
        // intact. stop() then no-ops and stopAndWait() falls through to `await stopDrain?.value`;
        // the mid-await start() still aborts via its post-await `guard isRunning` (now false).
        if transcriber == nil, capturePump == nil, segmentPump == nil { return nil }
        return (transcriber, capturePump, segmentPump)
    }

}

extension MeetingSession {
    // MARK: - Audio file transcription

    /// Transcribes audio pulled from `nextChunk` (e.g. an imported file) into the store, independent
    /// of live capture. `nextChunk` is called one chunk at a time and returns nil at end of input,
    /// so the transcriber's feed rate paces reading (no unbounded buffering). Creates its own
    /// transcriber, drains its segments into the store live, and finishes when input ends. Re-entry
    /// is ignored, and it waits for any prior transcriber to finish draining so two transcribers
    /// never run at once (avoids SFSpeechRecognizer's 1100 overlap error).
    ///
    /// `transcriber` lets the caller force a batch-friendly engine for imports (SpeechAnalyzer
    /// finalizes all fed audio, so fast-feeding is lossless); when nil the session's live factory
    /// is used.
    public func transcribeAudio(
        nextChunk: @escaping @Sendable () async -> AudioChunk?,
        transcriber makeTranscriber: (@Sendable () -> any Transcribing)? = nil
    ) async {
        guard !isTranscribingFile, !isRunning else { return }
        isTranscribingFile = true
        defer { isTranscribingFile = false }
        await stopDrain?.value
        stopDrain = nil
        let transcriber = (makeTranscriber ?? self.makeTranscriber)()
        transcriptionStatusTask?.cancel()
        transcriptionStatusTask = Task {
            for await status in transcriber.statusUpdates { self.transcriptionStatus = status }
        }
        defer { transcriptionStatusTask?.cancel() }
        let segmentStream = transcriber.segments
        let drain = Task { [weak self] in
            for await segment in segmentStream {
                self?.applyTranscribedSegment(segment)
            }
        }
        // Pace by audio duration so a long file can't be read into the transcriber's queue far
        // faster than it's processed: cap how far (in audio seconds) reading runs ahead of an
        // 8x-realtime budget. The clock starts AFTER the first feed so one-time SpeechAnalyzer
        // model setup/download isn't credited as throughput. Stops promptly on cancellation.
        var startWall = clock()
        var audioSecondsFed = 0.0
        var pacing = false
        while !Task.isCancelled, let chunk = await nextChunk() {
            await transcriber.feed(chunk)
            if !pacing { startWall = clock(); pacing = true; continue }   // exclude setup time
            audioSecondsFed += Double(chunk.samples.count) / max(chunk.sampleRate, 1)
            let lead = audioSecondsFed - (clock() - startWall) * 8.0
            if lead > 8.0 {
                try? await Task.sleep(nanoseconds: UInt64(min(lead, 5.0) * 1_000_000_000))
            }
        }
        await transcriber.finish()
        await drain.value
    }

    private func applyTranscribedSegment(_ segment: TranscriptSegment) {
        store.apply(segment)
    }

    // MARK: - Ingest

    /// Applies a segment to the store, fires proactive quick response when warranted,
    /// and schedules a batched evaluation for eligible live or finalized speech.
    public func ingest(_ segment: TranscriptSegment) async {
        store.apply(segment)

        handleLiveEvent(.transcriptChanged)
    }

    // MARK: - On-demand responses (awaitable)

    /// Transcript char budget for an action's prompt. Actions that summarize the whole conversation
    /// (a recap, or extracting every action item "so far") must cover the entire transcript, not just
    /// the recent window, so they get a far larger budget than on-the-spot answers.
    static func transcriptBudget(for action: ResponseAction) -> Int {
        switch action {
        case .recap, .actionItems: return 100_000
        default: return 4_000
        }
    }

    /// Streams a Quick response for the given action. Awaits completion.
    public func respondQuick(_ action: ResponseAction) async {
        await startRoleTask(.quick) {
            PromptBuilder.build(
                context: self.context.buildContext(from: self.store, notes: self.notes,
                                                   maxChars: Self.transcriptBudget(for: action),
                                                   summary: self.lastCompletedListenerSummary,
                                                   responseLanguage: self.responseLanguage,
                                                   references: self.referenceContext,
                                                   personaGuidance: self.personaGuidance),
                action: action)
        }.value
    }

    /// Streams a Deep response for the given action. Awaits completion.
    public func respondDeep(_ action: ResponseAction) async {
        await startRoleTask(.deep) {
            PromptBuilder.buildDeep(
                context: self.context.buildContext(from: self.store, notes: self.notes,
                                                   maxChars: Self.transcriptBudget(for: action),
                                                   summary: self.lastCompletedListenerSummary,
                                                   responseLanguage: self.responseLanguage,
                                                   references: self.referenceContext,
                                                   personaGuidance: self.personaGuidance),
                action: action)
        }.value
    }

    /// Streams a Listener refresh (rolling summary + open items). Awaits completion.
    public func refreshListener() async {
        startListenerRefresh()
        await waitForResponse(.listener)
    }

    /// New attribution should ground the next answer in the labeled transcript, not an older recap.
    public func speakerAttributionsChanged() {
        // Replay raw transcript when labels change so old names cannot survive only in generated prose.
        summarizedSegmentIDs = []
        lastCompletedListenerSummary = ""
        listenerSummary = ""
        startListenerRefresh()
    }

    /// Renaming invalidates prose produced with old names; rebuild the listener from the transcript.
    public func speakerNamesChanged() {
        for role in CopilotRole.allCases {
            responseTasks[role]?.cancel()
            responseGenerations[role, default: 0] += 1
        }
        streamingRoles = []
        quickSuggestion = ""
        deepAnswer = ""
        speakerAttributionsChanged()
    }

    // MARK: - Listener refresh starter

    /// Synchronously registers responseTasks[.listener] for a listener refresh and returns it.
    /// Shared by the ingest leading/trailing-edge debounce and the manual refreshListener().
    @discardableResult
    private func startListenerRefresh() -> Task<Void, Never> {
        let task = startRoleTask(.listener) {
            let remaining = self.store.utterances.filter { !self.summarizedSegmentIDs.contains($0.id) }
            // Process oldest unseen speech first. A failed/cancelled request never advances the ledger.
            var characters = 0
            let batch = remaining.prefix { segment in
                if characters > 0 && characters + segment.text.count > 16_000 { return false }
                characters += segment.text.count
                return true
            }
            let generation = self.responseGenerations[.listener] ?? 0
            self.pendingSummaryIDs[generation] = Set(batch.map(\.id))
            return PromptBuilder.buildListener(context: PromptContext(
                messages: Array(batch), notes: self.notes, summary: self.lastCompletedListenerSummary,
                responseLanguage: self.responseLanguage, personaGuidance: self.personaGuidance))
        }
        return task
    }

    // MARK: - Wait helpers

    /// Await the most recent in-flight task for the given role (for tests/UI).
    public func waitForResponse(_ role: CopilotRole) async {
        while let task = responseTasks[role] {
            let generation = responseGenerations[role]
            await task.value
            if generation == responseGenerations[role] { break }
        }
    }

    // MARK: - Internal per-role streaming machinery

    /// Cancels any prior task for `role`, starts a new one streaming `request` into
    /// that role's output property. Returns the task so callers can await it.
    @discardableResult
    private func startRoleTask(_ role: CopilotRole,
                               _ makeRequest: @escaping () -> LLMRequest) -> Task<Void, Never> {
        guard aiEnabled else { return Task {} }
        if role == .quick { handleLiveEvent(.manualQuickStarted) }
        responseTasks[role]?.cancel()
        let generation = (responseGenerations[role] ?? 0) + 1
        responseGenerations[role] = generation
        let request = makeRequest()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(role, request, generation: generation)
        }
        responseTasks[role] = task
        return task
    }

    private func run(_ role: CopilotRole, _ request: LLMRequest, generation: Int) async {
        guard generation == responseGenerations[role], !Task.isCancelled else { return }
        let reviewedPieces = livePieces
        // Clear the output and mark streaming
        setOutput(role, "")
        streamingRoles.insert(role)
        defer {
            if generation == responseGenerations[role] {
                streamingRoles.remove(role)
                if role == .quick { handleLiveEvent(.manualQuickFinished) }
            }
        }
        guard let provider = providers[role] else { return }
        do {
            for try await delta in provider.stream(request) {
                if Task.isCancelled { return }
                if generation != responseGenerations[role] { return }
                appendOutput(role, delta)
            }
            if generation == responseGenerations[role], !Task.isCancelled, reviewedPieces == livePieces {
                quickReader.markReviewed(role == .listener ? "summary" : role.rawValue)
            }
            // Listener finished: snapshot the completed summary for Quick/Deep grounding, so a
            // later refresh clearing the live value can't strip context from a proactive prompt.
            if role == .listener, generation == responseGenerations[role], !Task.isCancelled {
                lastCompletedListenerSummary = listenerSummary
                summarizedSegmentIDs.formUnion(pendingSummaryIDs[generation] ?? [])
                pendingSummaryIDs = [:]
                if aiEnabled && store.utterances.contains(where: { !summarizedSegmentIDs.contains($0.id) }) {
                    startListenerRefresh()
                }
            }
        } catch {
            if generation == responseGenerations[role],
               !Task.isCancelled,
               !(error is CancellationError) {
                appendOutput(role, "\n\n⚠️ \(error.localizedDescription)")
            }
        }
    }

    private func setOutput(_ role: CopilotRole, _ value: String) {
        switch role {
        case .listener: listenerSummary = value
        case .quick:    quickSuggestion = value
        case .deep:     deepAnswer = value
        }
    }

    private func appendOutput(_ role: CopilotRole, _ delta: String) {
        switch role {
        case .listener: listenerSummary += delta
        case .quick:    quickSuggestion += delta
        case .deep:     deepAnswer += delta
        }
    }
}


extension MeetingSession {
    private var livePieces: [QuickSummaryContext.Piece] {
        QuickSummaryContext.pieces(notes: notes, segments: store.utterances,
                                   liveSegments: [SpeakerSource.you, .others].compactMap { store.partials[$0] })
    }

    public var autoQuickStatus: String {
        guard autoSummaryEnabled else { return "Auto off" }
        guard aiEnabled else { return "Auto paused · AI is off" }
        if let reason = providerAvailability(models[.quick] ?? "") { return "Auto paused · " + reason }
        if let error = quickReader.error { return error }
        if quickReader.isCatchingUp { return "Catching up · Recap covers speech processed so far." }
        if quickReader.isReading { return "Checking new speech…" }
        return isRunning ? "Listening for meaningful changes" : "Auto checks while listening"
    }

    private func handleLiveEvent(_ event: LiveSummaryScheduler.Event) {
        let state = LiveSummaryScheduler.Snapshot(recording: isRunning, automatic: autoSummaryEnabled,
            pending: quickReader.context.hasChanges(livePieces), reading: quickReader.isReading,
            manualQuick: streamingRoles.contains(.quick), available: aiEnabled && providers[.quick] != nil && providerAvailability(models[.quick] ?? "") == nil,
            failures: quickReader.failures)
        for action in liveScheduler.plan(event, state: state) {
            switch action {
            case .cancelWake: liveWake?.cancel(); liveWake = nil
            case .cancelEvaluation: quickReader.cancel()
            case .schedule(let delay):
                liveWake = Task { [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    self?.handleLiveEvent(.timerFired)
                }
            case .evaluate: Task { [weak self] in await self?.evaluateLiveQuick() }
            }
        }
    }

    private func evaluateLiveQuick() async {
        guard isRunning, aiEnabled, autoSummaryEnabled, !quickReader.isReading,
              !streamingRoles.contains(.quick), providerAvailability(models[.quick] ?? "") == nil, let provider = providers[.quick] else { return }
        defer { handleLiveEvent(.evaluationFinished) }
        if livePieces.isEmpty { quickReader.reset(); quickSuggestion = ""; return }
        do {
            guard let batch = try quickReader.context.batch(livePieces, summary: quickSuggestion,
                reviewsCompleted: quickReader.reviewsCompleted, pendingReviews: quickReader.recommendations) else { return }
            let run = runID
            await quickReader.read(batch, provider: provider, isCurrent: { [weak self] in
                guard let self, self.runID == run, self.isRunning, self.autoSummaryEnabled, self.aiEnabled else { return false }
                return self.quickReader.context.isCurrent(batch, pieces: self.livePieces)
            }, apply: { [weak self] in self?.quickSuggestion = $0 })
        } catch { /* Encoding consists only of validated string data. A later event retries. */ }
    }
}
