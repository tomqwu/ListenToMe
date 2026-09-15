import Foundation
import Observation

/// Orchestrates capture -> transcription -> store -> proactive/on-demand responses
/// across three independent AI pane roles (Listener, Quick, Deep).
/// Depends only on protocols, so it is fully unit-testable with mocks.
@MainActor
@Observable
public final class MeetingSession {
    public private(set) var isRunning = false
    /// True between Start and the moment the transcription pipeline is warm — on a first run this
    /// covers a possibly multi-minute on-device speech-model download. The session is "running"
    /// (Stop is the way out) but no audio is being captured yet, so the UI shows PREP rather than
    /// REC and every automatic review is suppressed: without this gate the automation would fire
    /// against the *pre-existing* transcript while the header still says "preparing…" (issue #147).
    public private(set) var isPreparing = false
    public var notes = "" { didSet { handleLiveEvent(.notesChanged) } }
    public var proactiveEnabled = true
    public var autoSummaryEnabled = false { didSet { handleLiveEvent(.automationChanged) } }
    public var aiEnabled = true {
        didSet { if !aiEnabled { for role in CopilotRole.allCases { cancelResponse(role) } }; handleLiveEvent(.providerChanged) }
    }
    public private(set) var captureMessages: [SpeakerSource: String] = [:]
    /// Channels whose capture has failed mid-run (see `CaptureStatus.Severity.degraded`).
    private var degradedSources: Set<SpeakerSource> = []
    /// True while any channel is degraded — a dead mic after an input-device change, or a stopped
    /// system-audio stream. The UI shows this as a visible alert instead of a grey caption, because
    /// the rail keeps saying Recording and the elapsed timer keeps counting (issue #107).
    public var captureDegraded: Bool { !degradedSources.isEmpty }
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
    public internal(set) var quickSuggestion = ""
    public private(set) var deepAnswer = ""

    /// The automatic recap, kept apart from `quickSuggestion` (which also shows manual answers such
    /// as "Draft reply"). The evaluator always receives this as `visibleSummary`, so a manual answer
    /// can never be fed back as the current recap, and an automatic recap never overwrites a manual
    /// answer the user is still reading.
    public internal(set) var quickRecap = ""
    var manualQuickAnswer = ManualQuickAnswer()

    /// True while the Quick pane shows a *finished* answer that is not the current automatic recap.
    /// Deliberately independent of freshness — once the window elapses the pane keeps the answer
    /// until the next automatic apply, and the user must still be able to reach the newer recap —
    /// but never true mid-stream: a partial answer differs from the recap by definition, and
    /// replacing it while deltas keep appending would splice the recap and the answer's tail.
    public var quickAnswerOverridesRecap: Bool {
        !streamingRoles.contains(.quick) && !quickRecap.isEmpty && quickRecap != quickSuggestion
    }

    /// Drops the manual answer so the Quick pane follows the automatic recap again. A no-op unless
    /// the pane is actually holding a finished answer over a different recap.
    public func dismissQuickAnswer() {
        guard quickAnswerOverridesRecap else { return }
        manualQuickAnswer.dismiss()
        quickSuggestion = quickRecap
    }

    /// The last *completed* listener summary, used as grounding for Quick/Deep prompts. Kept
    /// separate from `listenerSummary` (the live display value, which is cleared to "" while a new
    /// refresh streams) so a proactive Quick can't read an empty/partial in-flight summary.
    var lastCompletedListenerSummary = ""
    var summarizedSegmentIDs = Set<UUID>()
    private var pendingSummaryIDs: [Int: Set<UUID>] = [:]
    /// The provisional (non-final) lines the last completed refresh actually sent. Unfinalized
    /// speech has no ledger entry — it is never final — so this is what keeps a second Refresh with
    /// the same unconfirmed wording a no-op (issues #113, #137).
    private var summarizedProvisionalText: String?
    private var pendingProvisionalText: [Int: String] = [:]
    /// Transcript characters one listener refresh asks for; also the window the Refresh button's
    /// provisional comparison measures, so the two always describe the same lines.
    static let listenerTranscriptBudget = 16_000

    /// Set when the last prompt had to drop transcript or reference material to fit the role
    /// provider's context window (Apple Intelligence). nil for providers with no window.
    public private(set) var promptTruncationNotice: String?

    /// The last failure for each pane, published separately from the pane's text so a transient
    /// provider error is shown as a banner *beside* the answer the user was reading instead of
    /// replacing it (issue #137). Cleared when that role starts a new run.
    public private(set) var roleErrors: [CopilotRole: String] = [:]

    /// The error banner a pane should show, or nil when its last run succeeded.
    public func roleError(_ role: CopilotRole) -> String? { roleErrors[role] }

    /// Transient per-role activity reported by the model while it works — currently a reasoning
    /// model's "Thinking…" phase, which streams `message.thinking` deltas before any answer token.
    /// It is a status only: reasoning is never written into the pane's text (issue #137).
    public private(set) var roleActivity: [CopilotRole: String] = [:]

    /// The activity line a pane should show beside its title, or nil when there is none.
    public func roleStatus(_ role: CopilotRole) -> String? { roleActivity[role] }

    /// True while an imported audio file is being transcribed into the store.
    public private(set) var isTranscribingFile = false

    /// The set of roles currently streaming a response.
    public private(set) var streamingRoles: Set<CopilotRole> = [] { didSet { synchronizeAutomaticReviews() } }

    /// The model ID assigned to each role.
    public private(set) var models: [CopilotRole: String]

    /// Memoized labeled-piece snapshot for the live path, keyed on `LiveKey`. Without it every
    /// ingested hypothesis walked the whole transcript several times on the main actor (issue #116).
    @ObservationIgnored var liveCacheKey: LiveKey?
    @ObservationIgnored var liveCache: LiveSnapshot?
    #if DEBUG
    /// Test-only: how many times the snapshot was actually rebuilt (cache misses).
    @ObservationIgnored var livePieceComputations = 0
    #endif

    public let quickReader = QuickSummaryReader()
    public let automaticReviews = AutomaticReviewCoordinator()
    var liveScheduler = LiveSummaryScheduler()
    var liveWake: Task<Void, Never>?

    private var context: ContextEngine
    private let makeCapture: @Sendable () -> any AudioCapturing
    private let makeTranscriber: @Sendable () -> any Transcribing
    let providerAvailability: @Sendable (String) -> String?
    private let makeProvider: @Sendable (String) -> any LLMProvider
    var providers: [CopilotRole: any LLMProvider]
    private var capture: (any AudioCapturing)?
    private var transcriber: (any Transcribing)?
    private let clock: @Sendable () -> TimeInterval

    /// Capture -> transcriber.feed pump. Drained (awaited) BEFORE finishing the transcriber so the
    /// last buffered chunks are fed before finalization — but only for `capturePumpDrainGrace`,
    /// after which `drain` cancels it so teardown can't hang behind a `feed` stuck in a one-time
    /// model download (issue #99). Because `prepare()` warms the pipeline before capture starts, a
    /// healthy pump drains far inside that grace period.
    private var capturePump: Task<Void, Never>?
    /// In-flight `transcriber.prepare()` (first-run speech-model download). Held so `beginStop()`
    /// can cancel it: otherwise Stop/New/window-close/Cmd-Q stay blocked for the whole download.
    private var prepareTask: Task<Void, Never>?
    /// transcriber.segments -> ingest pump. Drained AFTER finishing the transcriber so every final
    /// segment is ingested into the store.
    private var segmentPump: Task<Void, Never>?
    /// In-flight transcriber teardown from the last stop. `start()` awaits it before creating a new
    /// transcriber so a quick restart can't run two transcribers at once (SFSpeechRecognizer 1100).
    private var stopDrain: Task<Void, Never>?
    private var responseTasks: [CopilotRole: Task<Void, Never>] = [:]
    private var responseGenerations: [CopilotRole: Int] = [:]
    var runID = 0

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
        // The new provider may have a different context window (or none), so the old notice no
        // longer describes anything: it is re-derived on the next prompt.
        promptTruncationNotice = nil
        // The failure belonged to the previous model; it says nothing about this one (#137).
        roleErrors[role] = nil
        roleActivity[role] = nil
        if role == .quick { quickReader.clearError() }
        handleLiveEvent(.providerChanged)
    }

    public func cancelResponse(_ role: CopilotRole) {
        responseTasks[role]?.cancel()
        responseGenerations[role, default: 0] += 1
        streamingRoles.remove(role)
        // The bumped generation makes run()'s defer skip its own cleanup, so a cancelled reasoning
        // model would leave "Thinking…" on screen forever (issue #137).
        roleActivity[role] = nil
    }

    public func resetConversation() {
        guard !isRunning, !isTranscribingFile else { return }
        for role in CopilotRole.allCases { cancelResponse(role) }
        quickReader.reset(); handleLiveEvent(.conversationChanged)
        store.reset()
        notes = ""; referenceContext = nil
        listenerSummary = ""; quickSuggestion = ""; quickRecap = ""; deepAnswer = ""
        roleErrors = [:]; roleActivity = [:]
        manualQuickAnswer.dismiss()
        lastCompletedListenerSummary = ""
        summarizedSegmentIDs = []
        pendingSummaryIDs = [:]
        summarizedProvisionalText = nil
        pendingProvisionalText = [:]
        context = ContextEngine(debounce: context.debounce)
        runID += 1
    }

    // MARK: - Session lifecycle

    public func start() async throws {
        guard !isRunning, !isTranscribingFile else { return }
        isRunning = true
        isPreparing = true
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
        degradedSources = []
        transcriptionStatus = "Transcription: waiting for audio"
        captureStatusTask?.cancel(); transcriptionStatusTask?.cancel()
        captureStatusTask = Task {
            for await status in capture.statusUpdates {
                guard self.runID == myRun, self.isRunning else { break }
                self.captureMessages[status.source] = status.message
                // A degraded status latches until that same channel reports a healthy one again,
                // so one healthy channel can never hide the other's failure.
                if status.severity == .degraded {
                    self.degradedSources.insert(status.source)
                } else {
                    self.degradedSources.remove(status.source)
                }
            }
        }
        transcriptionStatusTask = Task {
            for await status in transcriber.statusUpdates {
                guard self.runID == myRun else { break }
                self.transcriptionStatus = status
            }
        }
        // Warm the transcription pipeline BEFORE any audio flows: on a first run this downloads the
        // on-device speech model (minutes), and doing it lazily on the feed path dropped the opening
        // seconds of both channels. Run it as a cancellable child Task so a Stop/close/quit during
        // the download tears down promptly instead of freezing the UI (issue #99).
        let prepare = Task { await transcriber.prepare() }
        prepareTask = prepare
        await prepare.value
        // A stop() during prepare already took ownership of the transcriber via beginStop() (and
        // cleared/cancelled this task), so leave its state alone and abort the start.
        guard isRunning, runID == myRun else { return }
        prepareTask = nil
        isPreparing = false
        handleLiveEvent(.recordingChanged)

        do {
            try await capture.start()
        } catch {
            capture.stop()
            if runID == myRun {
                isRunning = false
                isPreparing = false
                captureStatusTask?.cancel(); transcriptionStatusTask?.cancel()
                captureMessages = [.you: "start failed", .others: "stopped"]
                degradedSources = []
                transcriptionStatus = "Transcription: not started"
                self.capture = nil
                self.transcriber = nil
            }
            throw error
        }
        guard isRunning, runID == myRun else { capture.stop(); return }

        let captureStream = capture.chunks
        capturePump = Task {
            // `drain` cancels this pump if it hasn't finished feeding the stream's remaining chunks
            // within the grace period (i.e. a `feed` parked in a model download); the cancellation
            // reaches `feed` and ends the iteration, so no explicit cancellation check is wanted
            // here — that would drop the chunk already in hand.
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

    /// Grace period the capture pump gets to feed the chunks still buffered in the capture stream
    /// before teardown cancels it. `capture.stop()` has already finished the stream, so a healthy
    /// pump (warm pipeline ⇒ `feed` is a non-blocking hand-off) drains in microseconds and never
    /// reaches this deadline; only a pump parked inside a model download does (issue #99).
    private static let capturePumpDrainGrace: UInt64 = 250_000_000   // 250 ms

    /// Awaits full teardown in feed-before-finalize order: drain the capture pump (feed every
    /// remaining chunk, bounded by `capturePumpDrainGrace`), THEN finish the transcriber (finalize),
    /// THEN drain the segment pump (ingest every final into the store). This keeps the last buffered
    /// audio from being dropped by an early `finish()`, while guaranteeing teardown still returns
    /// promptly when `feed` is stuck in a first-run speech-model download.
    /// Static so it captures only the teardown payload, not `self`.
    /// One-shot thread-safe completion flag (a `Task`'s completion can only be observed by awaiting
    /// it, which is exactly what `prepareRacingCancellation` must avoid).
    private final class DoneFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        func set() { lock.withLock { _value = true } }
        var value: Bool { lock.withLock { _value } }
    }

    /// Runs `transcriber.prepare()` in a child task and waits for it in a way that ALSO returns as
    /// soon as the calling task is cancelled. `Transcribing.prepare()` is contracted to observe
    /// cancellation, but the platform calls it wraps may not (`AssetInventory.downloadAndInstall()`
    /// has no documented cancellation guarantee), and the import path's caller cancels the task and
    /// then awaits it — so a plain `await prepare()` could still block for the whole download.
    /// The abandoned child task is cancelled and left to unwind on its own (issue #99).
    private static func prepareRacingCancellation(_ transcriber: any Transcribing) async {
        let done = DoneFlag()
        let task = Task { await transcriber.prepare(); done.set() }
        while !done.value {
            if Task.isCancelled { task.cancel(); return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func drain(
        _ teardown: (transcriber: (any Transcribing)?,
                     capturePump: Task<Void, Never>?,
                     segmentPump: Task<Void, Never>?)
    ) async {
        if let pump = teardown.capturePump {
            let deadline = Task {
                try? await Task.sleep(nanoseconds: capturePumpDrainGrace)
                pump.cancel()
            }
            await pump.value
            deadline.cancel()
        }
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
        isPreparing = false
        handleLiveEvent(.recordingChanged)
        captureStatusTask?.cancel()
        captureMessages = [.you: "stopped", .others: "stopped"]
        degradedSources = []
        transcriptionStatus = "Transcription: finalizing…"
        for role in CopilotRole.allCases { cancelResponse(role) }
        capture?.stop()
        // Cancel, don't await: a first-run model download inside prepare() takes minutes, and
        // awaiting it kept lifecycleBusy true — freezing Stop, New, window close and Cmd-Q. The
        // capture pump is NOT cancelled here: `capture.stop()` finished its stream, so `drain`
        // lets it feed what's still buffered and only cancels it if that takes too long.
        prepareTask?.cancel()
        prepareTask = nil
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
        // Warm the pipeline before reading the file so the first chunks don't sit behind one-time
        // model setup, and so a cancelled import isn't stuck inside `feed`. Waited for through
        // `prepareRacingCancellation` because the caller (window close) cancels the import task and
        // then awaits it: we must return as soon as we're cancelled even if the platform's download
        // call ignores cancellation.
        await Self.prepareRacingCancellation(transcriber)
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

    /// Trims `value` to `allowance`, reporting whether anything was cut. nil out when nothing is left.
    private static func clamp(_ value: String, to allowance: Int) -> (String?, dropped: Bool) {
        guard !value.isEmpty else { return (nil, false) }
        guard value.count > allowance else { return (value, false) }
        let kept = String(value.prefix(allowance)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (kept.isEmpty ? nil : kept, true)
    }

    /// Builds the prompt context for `role`, bounding the *assembled* prompt to that provider's
    /// context window: the scaffold (system prompt, directives, headers, instruction) is measured,
    /// and transcript, references, summary and notes divide what is left. Transcript characters are
    /// charged with their speaker labels. With no window (Ollama) every budget is untouched.
    private func clampedContext(for action: ResponseAction, role: CopilotRole,
                                kind: PromptBuilder.Kind) -> PromptContext {
        let limit = providers[role]?.maxPromptCharacters
        let references = referenceContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = lastCompletedListenerSummary
        let scaffold = limit == nil ? 0 : PromptBuilder.scaffoldCharacterCost(
            kind: kind,
            context: PromptContext(messages: [], notes: notes, summary: summary,
                                   responseLanguage: responseLanguage,
                                   references: references.isEmpty ? nil : references,
                                   personaGuidance: personaGuidance),
            action: action)
        // The provisional notice is part of the assembled prompt but invisible to the scaffold probe,
        // which measures with no messages. Charge it whenever a hypothesis is eligible, so the
        // definition cannot be what pushes an Apple-sized prompt over its window.
        let notice = store.hasProvisionalSpeech ? PromptBuilder.provisionalNotice.count + 2 : 0
        let allocation = PromptBudget.allocate(
            limit: limit, scaffold: scaffold + notice, transcript: Self.transcriptBudget(for: action),
            references: references.count, summary: summary.count, notes: notes.count)

        let (clampedReferences, droppedReferences) = Self.clamp(references, to: allocation.references)
        let (clampedSummary, droppedSummary) = Self.clamp(summary, to: allocation.summary)
        let (clampedNotes, droppedNotes) = Self.clamp(notes, to: allocation.notes)
        let context = self.context.buildContext(
            from: store, notes: clampedNotes, maxChars: allocation.transcript,
            summary: clampedSummary, responseLanguage: responseLanguage,
            references: clampedReferences, personaGuidance: personaGuidance)
        // Only a context-window clamp is worth reporting; the provider-agnostic "recent window"
        // budgets have always been a deliberate relevance choice, not a capacity failure.
        // Only finalized lines are compared: the trailing provisional lines are extra context, not
        // part of the transcript window that could have been trimmed.
        let droppedTranscript = context.messages.count(where: \.isFinal) < store.utterances.count
        promptTruncationNotice = limit == nil ? nil : PromptBudget.truncationNotice(
            transcriptDropped: droppedTranscript, referencesDropped: droppedReferences,
            auxiliaryDropped: droppedSummary || droppedNotes)
        return context
    }

    /// Streams a Quick response for the given action. Awaits completion.
    public func respondQuick(_ action: ResponseAction) async {
        await startRoleTask(.quick) {
            PromptBuilder.build(context: self.clampedContext(for: action, role: .quick, kind: .quick),
                                action: action)
        }.value
    }

    /// Streams a Deep response for the given action. Awaits completion.
    public func respondDeep(_ action: ResponseAction) async {
        await startRoleTask(.deep) {
            PromptBuilder.buildDeep(context: self.clampedContext(for: action, role: .deep, kind: .deep),
                                    action: action)
        }.value
    }

    /// True when the store holds speech the Listener has not summarized yet: finalized utterances
    /// outside its ledger, or unfinalized speech whose wording differs from what the last refresh
    /// already sent as provisional context (issue #113) — a caught-up refresh carries that instead.
    /// A refresh with nothing new is a no-op, so the UI disables Refresh on `!hasUnsummarizedSpeech`
    /// (issue #137).
    public var hasUnsummarizedSpeech: Bool {
        if store.utterances.contains(where: { !summarizedSegmentIDs.contains($0.id) }) { return true }
        guard store.hasProvisionalSpeech else { return false }
        return Self.signature(of: store.provisionalContext(maxChars: Self.listenerTranscriptBudget))
            != summarizedProvisionalText
    }

    /// The provisional lines a refresh sends, as one comparable string.
    static func signature(of segments: [TranscriptSegment]) -> String {
        segments.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n")
    }

    /// Streams a Listener refresh (rolling summary + open items). Awaits completion.
    public func refreshListener() async {
        guard hasUnsummarizedSpeech else { return }
        startListenerRefresh()
        await waitForResponse(.listener)
    }

    /// New attribution should ground the next answer in the labeled transcript, not an older recap.
    ///
    /// This still re-summarizes the whole meeting, even with Auto off — tracked as #167 (part of
    /// #98) and deliberately out of scope for #137, which only stopped the *no-op* refresh.
    public func speakerAttributionsChanged() {
        // Replay raw transcript when labels change so old names cannot survive only in generated prose.
        summarizedSegmentIDs = []
        summarizedProvisionalText = nil
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
        quickRecap = ""
        manualQuickAnswer.dismiss()
        deepAnswer = ""
        speakerAttributionsChanged()
    }

    // MARK: - Listener refresh starter

    /// Synchronously registers responseTasks[.listener] for a listener refresh and returns it.
    /// Shared by the ingest leading/trailing-edge debounce and the manual refreshListener().
    @discardableResult
    private func startListenerRefresh() -> Task<Void, Never> {
        // Nothing to summarize is not a request: an empty store has no meeting to describe, and a
        // fully summarized transcript would only send "New transcript evidence:" with nothing after
        // it and have the model re-paraphrase — and possibly drop items from — the record it just
        // produced (issue #137). Unfinalized speech still counts: with the ledger caught up, the
        // refresh carries the provisional lines instead (issue #113). The Refresh button is
        // disabled on the same condition.
        guard hasUnsummarizedSpeech else { return Task {} }
        let task = startRoleTask(.listener) {
            let remaining = self.store.utterances.filter { !self.summarizedSegmentIDs.contains($0.id) }
            // Process oldest unseen speech first. A failed/cancelled request never advances the ledger.
            // The whole assembled prompt — batch, previous record and notes — is bounded by the
            // listener provider's context window (nil = unlimited).
            let limit = self.providers[.listener]?.maxPromptCharacters
            let record = self.lastCompletedListenerSummary
            let scaffold = limit == nil ? 0 : PromptBuilder.scaffoldCharacterCost(
                kind: .listener,
                context: PromptContext(messages: [], notes: self.notes, summary: record,
                                       responseLanguage: self.responseLanguage,
                                       personaGuidance: self.personaGuidance),
                action: .recap)
            // Charged only when this refresh will actually carry provisional lines — the listener
            // sends them solely once the ledger has caught up (see below).
            let notice = remaining.isEmpty && self.store.hasProvisionalSpeech
                ? PromptBuilder.provisionalNotice.count + 2 : 0
            let allocation = PromptBudget.allocate(
                limit: limit, scaffold: scaffold + notice, transcript: Self.listenerTranscriptBudget, references: 0,
                summary: record.count, notes: self.notes.count)
            let (clampedRecord, droppedRecord) = Self.clamp(record, to: allocation.summary)
            let (clampedNotes, droppedNotes) = Self.clamp(self.notes, to: allocation.notes)
            // Speech the recognizer has not finalized is appended as trailing "(provisional)" lines
            // so a refresh cannot miss a hypothesis that stays volatile for the whole recording
            // (issue #113) — but ONLY when the ledger has caught up. The listener's record is
            // cumulative and each chained batch would otherwise re-send the same unconfirmed
            // wording, and the rolling record is what a chained batch builds on. Being non-final,
            // these lines never enter `pendingSummaryIDs`, so the real segment is still summarized
            // once it finalizes, and `PromptBuilder` tells the model what the tag means.
            var characters = 0
            let batch = remaining.prefix { segment in
                let cost = TranscriptSegment.promptCharacterCost(segment)
                if characters > 0 && characters + cost > allocation.transcript { return false }
                characters += cost
                return true
            }
            let provisional = remaining.isEmpty
                ? self.store.provisionalContext(maxChars: allocation.transcript) : []
            // A partial batch is not loss: the ledger keeps the rest and a follow-up refresh starts
            // automatically, so only a clamped record or notes is worth reporting here. Report by
            // assignment only — an ordinary batched refresh (Refresh, rename, the auto-continue
            // chain) must never erase a still-valid Quick/Deep notice; clearing belongs to
            // clampedContext and setModel.
            if limit != nil, let notice = PromptBudget.truncationNotice(
                transcriptDropped: false, referencesDropped: false,
                auxiliaryDropped: droppedRecord || droppedNotes) {
                self.promptTruncationNotice = notice
            }
            let generation = self.responseGenerations[.listener] ?? 0
            self.pendingSummaryIDs[generation] = Set(batch.map(\.id))
            // Provisional lines never become ledger entries (they are not final), so what this
            // refresh sent is remembered separately and keeps Refresh disabled until the wording
            // changes or the recognizer finalizes it (issues #113, #137).
            self.pendingProvisionalText[generation] = provisional.isEmpty
                ? nil : Self.signature(of: provisional)
            return PromptBuilder.buildListener(context: PromptContext(
                messages: Array(batch) + provisional, notes: clampedNotes, summary: clampedRecord ?? "",
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
        streamingRoles.insert(role)
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
        // A new manual request replaces the answer on screen; it only protects the pane again once
        // it has actually produced one.
        if role == .quick { manualQuickAnswer.dismiss() }
        // What the pane is showing right now. A non-cancellation failure restores it rather than
        // leaving the user with an empty pane and a warning (issue #137).
        let previousOutput = output(role)
        // Clear the output and mark streaming
        setOutput(role, "")
        roleErrors[role] = nil
        roleActivity[role] = nil
        streamingRoles.insert(role)
        defer {
            if generation == responseGenerations[role] {
                streamingRoles.remove(role)
                roleActivity[role] = nil
                if role == .quick { handleLiveEvent(.manualQuickFinished) }
            }
        }
        guard let provider = providers[role] else { return }
        do {
            for try await event in provider.streamEvents(request) {
                if Task.isCancelled { return }
                if generation != responseGenerations[role] { return }
                switch event {
                case .thinking:
                    // Reasoning is progress, not an answer: show it as a status so a 30-120 s
                    // think phase does not look like a hung request (issue #137).
                    roleActivity[role] = "Thinking…"
                case .content(let delta):
                    roleActivity[role] = nil
                    appendOutput(role, delta)
                }
            }
            // Quick has no automatic review mode; a completed manual answer instead holds the pane
            // against the automatic recap for a bounded time.
            if role == .quick, generation == responseGenerations[role], !Task.isCancelled,
               !quickSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                manualQuickAnswer.completed(at: clock())
            }
            if generation == responseGenerations[role], !Task.isCancelled,
               let mode = AutomaticReviewMode(rawValue: role == .listener ? "summary" : role.rawValue) {
                automaticReviews.markManualCompletion(mode, source: reviewedPieces.map(\.text).joined(separator: "\n"))
            }
            // Notes typed, or speech appended, while the manual answer streamed do not make the
            // answer stale: the same continuation rule that keeps an automatic review alive decides
            // whether this one still covers what is on screen.
            if generation == responseGenerations[role], !Task.isCancelled,
               QuickSummaryContext.isContinuation(of: reviewedPieces, in: livePieces) {
                quickReader.markReviewed(role == .listener ? "summary" : role.rawValue)
            }
            // Listener finished: snapshot the completed summary for Quick/Deep grounding, so a
            // later refresh clearing the live value can't strip context from a proactive prompt.
            if role == .listener, generation == responseGenerations[role], !Task.isCancelled {
                lastCompletedListenerSummary = listenerSummary
                summarizedSegmentIDs.formUnion(pendingSummaryIDs[generation] ?? [])
                pendingSummaryIDs = [:]
                summarizedProvisionalText = pendingProvisionalText[generation]
                pendingProvisionalText = [:]
                if aiEnabled && store.utterances.contains(where: { !summarizedSegmentIDs.contains($0.id) }) {
                    startListenerRefresh()
                }
            }
        } catch {
            if generation == responseGenerations[role],
               !Task.isCancelled,
               !(error is CancellationError) {
                // Keep what the user was reading: restore the previous answer when this attempt
                // produced nothing, and keep the partial stream when it did (an interrupted
                // response is still text the user can use). The failure itself is published
                // through `roleErrors`, which the pane renders as its own banner, so a transient
                // provider error never blanks a pane — matching the automatic paths, which have
                // always kept previous output (issue #137).
                if output(role).isEmpty { setOutput(role, previousOutput) }
                roleErrors[role] = error.localizedDescription
            }
        }
    }

    /// Stores a new automatic recap. It always becomes the evaluator's grounding; it reaches the
    /// Quick pane only when no manual answer is still fresh, so an answer the user requested is
    /// never replaced mid-read by three automatic bullets.
    func applyQuickRecap(_ output: String) {
        quickRecap = output
        guard !manualQuickAnswer.isFresh(at: clock()) else { return }
        quickSuggestion = output
    }

    private func output(_ role: CopilotRole) -> String {
        switch role {
        case .listener: return listenerSummary
        case .quick:    return quickSuggestion
        case .deep:     return deepAnswer
        }
    }

    func setOutput(_ role: CopilotRole, _ value: String) {
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
