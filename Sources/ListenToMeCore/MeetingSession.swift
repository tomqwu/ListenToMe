import Foundation
import Observation

/// Orchestrates capture -> transcription -> store -> proactive/on-demand responses
/// across three independent AI pane roles (Listener, Quick, Deep).
/// Depends only on protocols, so it is fully unit-testable with mocks.
@MainActor
@Observable
public final class MeetingSession {
    public private(set) var isRunning = false
    public var notes = ""
    public var proactiveEnabled = true
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

    /// True while an imported audio file is being transcribed into the store.
    public private(set) var isTranscribingFile = false

    /// The set of roles currently streaming a response.
    public private(set) var streamingRoles: Set<CopilotRole> = []

    /// The model ID assigned to each role.
    public private(set) var models: [CopilotRole: String]

    private var context: ContextEngine
    private let makeCapture: @Sendable () -> any AudioCapturing
    private let makeTranscriber: @Sendable () -> any Transcribing
    private let makeProvider: @Sendable (String) -> any LLMProvider
    private var providers: [CopilotRole: any LLMProvider]
    private var capture: (any AudioCapturing)?
    private var transcriber: (any Transcribing)?
    private let clock: @Sendable () -> TimeInterval
    private let listenerDebounce: TimeInterval

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

    /// Tracks when the listener was last refreshed (for debouncing ingest-triggered refreshes).
    private var lastListenerFire: TimeInterval = -.greatestFiniteMagnitude

    /// True while a coalesced trailing listener refresh is scheduled (at most one in flight).
    private var listenerRefreshPending = false

    public init(store: ConversationStore,
                context: ContextEngine,
                makeCapture: @escaping @Sendable () -> any AudioCapturing,
                makeTranscriber: @escaping @Sendable () -> any Transcribing,
                makeProvider: @escaping @Sendable (String) -> any LLMProvider,
                models: [CopilotRole: String],
                listenerDebounce: TimeInterval = 12,
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.context = context
        self.makeCapture = makeCapture
        self.makeTranscriber = makeTranscriber
        self.makeProvider = makeProvider
        self.models = models
        self.listenerDebounce = listenerDebounce
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
        models[role] = model
        providers[role] = makeProvider(model)
    }

    // MARK: - Session lifecycle

    public func start() async throws {
        guard !isRunning, !isTranscribingFile else { return }
        isRunning = true
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
        do {
            try await capture.start()
        } catch {
            capture.stop()
            if runID == myRun {
                isRunning = false
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
        listenerRefreshPending = false
        for (_, task) in responseTasks { task.cancel() }
        capture?.stop()
        let transcriber = self.transcriber
        let capturePump = self.capturePump
        let segmentPump = self.segmentPump
        capture = nil
        self.transcriber = nil
        self.capturePump = nil
        self.segmentPump = nil
        return (transcriber, capturePump, segmentPump)
    }

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
        let segmentStream = transcriber.segments
        let drain = Task { [weak self] in
            for await segment in segmentStream {
                await self?.applyTranscribedSegment(segment)
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
    /// and schedules a debounced listener refresh for finalized segments.
    public func ingest(_ segment: TranscriptSegment) async {
        store.apply(segment)

        // Listener refresh: leading + trailing edge debounce on finalized segments while running.
        // Leading edge fires immediately and registers responseTasks[.listener] synchronously
        // (via startListenerRefresh) so stop()/waitForResponse(.listener) cannot miss it.
        // Suppressed segments arm a single coalesced trailing refresh for the rest of the window,
        // so a final utterance before the meeting goes quiet still gets summarized.
        if segment.isFinal, isRunning {
            let now = clock()
            let elapsed = now - lastListenerFire
            if elapsed >= listenerDebounce {
                lastListenerFire = now
                startListenerRefresh()
            } else if !listenerRefreshPending {
                listenerRefreshPending = true
                let wait = listenerDebounce - elapsed
                let scheduledRun = runID
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
                    self?.fireTrailingListenerRefresh(forRun: scheduledRun)
                }
            }
        }

        // Quick proactive: fires on finalized remote questions
        guard isRunning, proactiveEnabled,
              context.shouldFireProactive(for: segment, now: clock()) else { return }
        startRoleTask(.quick) {
            PromptBuilder.build(
                context: self.context.buildContext(from: self.store, notes: self.notes,
                                                   summary: self.lastCompletedListenerSummary,
                                                   responseLanguage: self.responseLanguage,
                                                   references: self.referenceContext,
                                                   personaGuidance: self.personaGuidance),
                action: .proactive)
        }
    }

    // MARK: - On-demand responses (awaitable)

    /// Transcript char budget for an action's prompt. A recap should cover the whole conversation,
    /// not just the recent window, so it gets a far larger budget than on-the-spot answers.
    static func transcriptBudget(for action: ResponseAction) -> Int {
        action == .recap ? 100_000 : 4_000
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
        await startListenerRefresh().value
    }

    // MARK: - Listener refresh starter

    /// Synchronously registers responseTasks[.listener] for a listener refresh and returns it.
    /// Shared by the ingest leading/trailing-edge debounce and the manual refreshListener().
    @discardableResult
    private func startListenerRefresh() -> Task<Void, Never> {
        startRoleTask(.listener) {
            PromptBuilder.buildListener(context: self.context.buildContext(from: self.store, notes: self.notes,
                                        responseLanguage: self.responseLanguage,
                                        personaGuidance: self.personaGuidance))
        }
    }

    /// Fires a coalesced trailing listener refresh after the debounce window, unless stopped
    /// or the session has been restarted (stale cross-session refresh).
    private func fireTrailingListenerRefresh(forRun run: Int) {
        listenerRefreshPending = false
        guard isRunning, runID == run else { return }   // ignore stale cross-session refreshes
        lastListenerFire = clock()
        startListenerRefresh()
    }

    // MARK: - Wait helpers

    /// Await the most recent in-flight task for the given role (for tests/UI).
    public func waitForResponse(_ role: CopilotRole) async {
        await responseTasks[role]?.value
    }

    // MARK: - Internal per-role streaming machinery

    /// Cancels any prior task for `role`, starts a new one streaming `request` into
    /// that role's output property. Returns the task so callers can await it.
    @discardableResult
    private func startRoleTask(_ role: CopilotRole,
                               _ makeRequest: @escaping () -> LLMRequest) -> Task<Void, Never> {
        responseTasks[role]?.cancel()
        let generation = (responseGenerations[role] ?? 0) + 1
        responseGenerations[role] = generation
        let task = Task { [weak self] in
            guard let self else { return }
            let request = makeRequest()
            await self.run(role, request, generation: generation)
        }
        responseTasks[role] = task
        return task
    }

    private func run(_ role: CopilotRole, _ request: LLMRequest, generation: Int) async {
        guard generation == responseGenerations[role], !Task.isCancelled else { return }
        // Clear the output and mark streaming
        setOutput(role, "")
        streamingRoles.insert(role)
        defer {
            if generation == responseGenerations[role] {
                streamingRoles.remove(role)
            }
        }
        guard let provider = providers[role] else { return }
        do {
            for try await delta in provider.stream(request) {
                if Task.isCancelled { return }
                if generation != responseGenerations[role] { return }
                appendOutput(role, delta)
            }
            // Listener finished: snapshot the completed summary for Quick/Deep grounding, so a
            // later refresh clearing the live value can't strip context from a proactive prompt.
            if role == .listener, generation == responseGenerations[role], !Task.isCancelled {
                lastCompletedListenerSummary = listenerSummary
            }
        } catch {
            if generation == responseGenerations[role],
               !Task.isCancelled,
               !(error is CancellationError) {
                setOutput(role, "⚠️ \(error.localizedDescription)")
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
