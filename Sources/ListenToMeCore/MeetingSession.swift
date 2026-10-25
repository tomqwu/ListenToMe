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
    /// When on (the default), a finalized question from the *other* party automatically fires a
    /// Quick answer — the live-copilot behaviour README and the smoke test promise. It is a
    /// manual-style answer that happens to be triggered automatically, so it runs through the same
    /// `respondQuick` path (and the same manual-answer freshness rules) as the buttons; it is
    /// independent of `autoSummaryEnabled`, which drives the periodic automatic recap instead.
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
    public internal(set) var transcriptionStatus = "Transcription: idle"
    public var captureStatus: String {
        "Mic: \(captureMessages[.you] ?? "idle") · System: \(captureMessages[.others] ?? "idle")"
    }
    private var captureStatusTask: Task<Void, Never>?
    var transcriptionStatusTask: Task<Void, Never>?

    /// Forces all AI replies (Listener/Quick/Deep) into this language, e.g. "Simplified Chinese";
    /// nil/empty leaves the model free to match the conversation. Set from the UI's Settings.
    public var responseLanguage: String?
    /// Attached reference material (file/folder contents) fed into Quick/Deep prompts as grounding;
    /// nil/empty = none. Set from the UI when the user attaches files.
    public var referenceContext: String?
    /// Use-case persona guidance from the selected preset, injected into all pane prompts.
    public var summaryInstructions = "" { didSet { handleLiveEvent(.notesChanged) } }
    public var personaGuidance: String?
    /// The active vocabularies' recognition terms (issue #222). Handed to each new transcriber before it
    /// prepares, and to the running one as soon as they change, so an Add during recording needs no restart.
    /// Summary-only guidance (issue #222): the active vocabulary's summary headings, added to the
    /// Listener's prompt and to automatic Summary reviews but never to Quick or Deep.
    public var summaryGuidance: String?
    public var contextualStrings: [String] = [] {
        didSet {
            guard contextualStrings != oldValue, let transcriber else { return }
            let strings = contextualStrings
            Task { await transcriber.setContextualStrings(strings) }
        }
    }
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
    /// What each pane's notices say and the exact text they describe (issues #114, #215). A notice is
    /// shown only while the pane still shows that text, so every path that replaces or clears it — an
    /// automatic recap, a failed request restoring the previous answer, a rename — drops it too.
    var roleNoticeRecords: [CopilotRole: RoleNoticeRecord] = [:]
    /// The grounding line of the request a pane is streaming now, shown while it streams.
    var pendingGrounding: [CopilotRole: String] = [:]
    /// True when the last completed Listener summary stopped at the output limit, so it is never
    /// treated as covering the speech it read (issue #114).
    var listenerSummaryCutOff = false

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
    public internal(set) var isTranscribingFile = false
    /// A decode failure or cancellation left only part of an imported file in this conversation.
    public internal(set) var hasIncompleteImport = false

    /// Where the current recording starts on the conversation's timeline (review of #233): each
    /// capture's engine times restart at zero, so its timed lines are moved past the end of the
    /// lines already there, as iOS does. Untimed lines (SpeechAnalyzer until #68) stay untimed.
    public private(set) var recordingOffset: TimeInterval = 0

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
    let makeTranscriber: @Sendable () -> any Transcribing
    let providerAvailability: @Sendable (String) -> String?
    private let makeProvider: @Sendable (String) -> any LLMProvider
    var providers: [CopilotRole: any LLMProvider]
    private var capture: (any AudioCapturing)?
    private var transcriber: (any Transcribing)?
    let clock: @Sendable () -> TimeInterval
    /// See `drain(_:grace:)`. Injectable so a test's own per-chunk feed cost can't race the
    /// default deadline (issue #147).
    private let capturePumpDrainGrace: Duration

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
    var stopDrain: Task<Void, Never>?
    /// In-flight automatic (proactive) Quick fire started from `ingest`.
    private var proactiveTask: Task<Void, Never>?
    private var responseTasks: [CopilotRole: Task<Void, Never>] = [:]
    private var responseGenerations: [CopilotRole: Int] = [:]
    var runID = 0

    public init(store: ConversationStore,
                context: ContextEngine,
                makeCapture: @escaping @Sendable () -> any AudioCapturing,
                makeTranscriber: @escaping @Sendable () -> any Transcribing,
                makeProvider: @escaping @Sendable (String) -> any LLMProvider,
                models: [CopilotRole: String],
                autoInterval: Duration = .seconds(5),
                capturePumpDrainGrace: Duration = .milliseconds(250),
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
        self.capturePumpDrainGrace = capturePumpDrainGrace
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
        stoppedResponseText[role] = nil
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

    /// Explicit user cancellation keeps the partial answer without marking its source as reviewed.
    private var stoppedResponseText: [CopilotRole: String] = [:]
    public var stoppedResponseRoles: Set<CopilotRole> {
        Set(stoppedResponseText.compactMap { role, text in output(role) == text ? role : nil })
    }

    public func stopResponse(_ role: CopilotRole) {
        guard streamingRoles.contains(role) else { return }
        cancelResponse(role)
        stoppedResponseText[role] = output(role)
        if role == .quick {
            if !quickSuggestion.isEmpty { manualQuickAnswer.completed(at: clock()) }
            handleLiveEvent(.manualQuickFinished)
        }
    }

    public func cancelResponse(_ role: CopilotRole) {
        responseTasks[role]?.cancel()
        responseGenerations[role, default: 0] += 1
        streamingRoles.remove(role)
        // The bumped generation makes run()'s defer skip its own cleanup, so a cancelled reasoning
        // model would leave "Thinking…" on screen forever (issue #137).
        roleActivity[role] = nil
    }

    /// Reopens a saved modern record without treating restored summaries as newly reviewed speech.
    @discardableResult
    public func restoreConversation(_ record: SessionRecord) -> Bool {
        guard !isRunning, !isTranscribingFile, record.segments != nil || record.transcript.isEmpty else { return false }
        resetConversation()
        store.restore(record.segments ?? [])
        hasIncompleteImport = record.hasIncompleteImport == true
        notes = record.notes ?? ""
        summaryInstructions = record.summaryInstructions ?? ""
        listenerSummary = record.summary
        lastCompletedListenerSummary = record.summary
        quickSuggestion = record.quickSuggestion ?? ""
        deepAnswer = record.deepAnswer ?? ""
        return true
    }

    public func resetConversation() {
        guard !isRunning, !isTranscribingFile else { return }
        for role in CopilotRole.allCases { cancelResponse(role) }
        // No proactive task needs cancelling here: `ingest` only fires while running, and `stop()`
        // (which must precede a reset) already cancelled it.
        quickReader.reset(); handleLiveEvent(.conversationChanged)
        store.reset(); recordingOffset = 0; hasIncompleteImport = false
        notes = ""; summaryInstructions = ""; referenceContext = nil
        listenerSummary = ""; quickSuggestion = ""; quickRecap = ""; deepAnswer = ""
        roleErrors = [:]; roleActivity = [:]; roleNoticeRecords = [:]; pendingGrounding = [:]
        stoppedResponseText.removeAll()
        manualQuickAnswer.dismiss()
        lastCompletedListenerSummary = ""; listenerSummaryCutOff = false
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
        startRecordingTimeline()
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
        // Waited for through `prepareRacingCancellation` (as on the import path): `prepare()` is
        // contracted to observe cancellation but the platform download it wraps may not
        // (`AssetInventory.downloadAndInstall()` has no documented guarantee), so a plain
        // `await transcriber.prepare()` could park this start task for the whole download after a
        // Stop — and the next Listen would then run a second concurrent download (issue #147).
        await transcriber.setContextualStrings(contextualStrings)
        guard isRunning, runID == myRun else { return }   // stopped while the vocabulary was handed over
        let prepare = Task { await Self.prepareRacingCancellation(transcriber) }
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
        stopDrain = Task { [grace = capturePumpDrainGrace] in await Self.drain(teardown, grace: grace) }
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
        let drain = Task { [grace = capturePumpDrainGrace] in await Self.drain(teardown, grace: grace) }
        stopDrain = drain
        await drain.value
        transcriptionStatusTask?.cancel()
        if transcriptionStatus.hasPrefix("Transcription:") { transcriptionStatus = "Transcription: stopped" }
    }

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
    static func prepareRacingCancellation(_ transcriber: any Transcribing) async {
        let done = DoneFlag()
        let task = Task { await transcriber.prepare(); done.set() }
        while !done.value {
            if Task.isCancelled { task.cancel(); return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Awaits full teardown in feed-before-finalize order: drain the capture pump (feed every
    /// remaining chunk, bounded by `grace`), THEN finish the transcriber (finalize), THEN drain the
    /// segment pump (ingest every final into the store). This keeps the last buffered audio from
    /// being dropped by an early `finish()`, while guaranteeing teardown still returns promptly when
    /// `feed` is stuck in a first-run speech-model download.
    /// Static so it captures only the teardown payload, not `self`.
    ///
    /// - Parameter grace: how long the capture pump gets to feed the chunks still buffered in the
    ///   capture stream before it is cancelled. `capture.stop()` has already finished the stream, so
    ///   a healthy pump (warm pipeline ⇒ `feed` is a non-blocking hand-off) drains in microseconds
    ///   and never reaches this deadline; only a pump parked inside a model download does (#99).
    ///   Injectable through `init(capturePumpDrainGrace:)` so a test's own feed cost can't race it.
    private static func drain(
        _ teardown: (transcriber: (any Transcribing)?,
                     capturePump: Task<Void, Never>?,
                     segmentPump: Task<Void, Never>?),
        grace: Duration
    ) async {
        if let pump = teardown.capturePump {
            let deadline = Task {
                try? await Task.sleep(for: grace)
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
        proactiveTask?.cancel(); proactiveTask = nil
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
    func applyTranscribedSegment(_ segment: TranscriptSegment) {
        store.apply(segment.shifted(by: recordingOffset))
    }

    /// A new recording continues after the conversation's last timed line.
    func startRecordingTimeline() {
        recordingOffset = store.utterances.filter(TranscriptTimestamp.isTimed).map(\.end).max() ?? 0
    }

    // MARK: - Ingest

    /// Applies a segment to the store, schedules a batched evaluation for eligible live or
    /// finalized speech, and fires a proactive Quick answer when the other party asks a question.
    public func ingest(_ segment: TranscriptSegment) async {
        store.apply(segment.shifted(by: recordingOffset))

        handleLiveEvent(.transcriptChanged)
        fireProactiveIfWarranted(for: segment)
    }

    /// Starts an automatic Quick answer for a finalized question from `.others`.
    ///
    /// Deliberately *not* awaited by `ingest`: the segment pump must keep draining the transcriber
    /// while the answer streams. Every guard the manual path applies applies here too — AI off, no
    /// Quick provider, or an unavailable model means no request — plus four that are specific to
    /// firing without the user asking: the own-speech exclusion and the debounce live in
    /// `ContextEngine.shouldFireProactive`, a manual Quick that is still streaming is never
    /// interrupted by an automatic one, and nothing fires while the speech model is still preparing
    /// — no audio is flowing yet, so anything ingested then is pre-existing transcript rather than a
    /// question the other party just asked (the rule automatic reviews follow, issue #147).
    private func fireProactiveIfWarranted(for segment: TranscriptSegment) {
        guard proactiveEnabled, isRunning, !isPreparing, aiEnabled,
              !streamingRoles.contains(.quick),
              providers[.quick] != nil,
              providerAvailability(models[.quick] ?? "") == nil,
              context.shouldFireProactive(for: segment, now: clock()) else { return }
        proactiveTask?.cancel()
        proactiveTask = Task { [weak self] in
            guard let self else { return }
            // The run can end — or end and restart — between the decision and this body being
            // scheduled, and a question from a finished session must never answer into the next
            // one. `stop()`, `resetConversation()` and a newer fire all cancel this task, and that
            // cancellation is what carries across a restart: comparing `runID` would not, because
            // `start()` sets `isRunning` back to true and bumps `runID` only *after* awaiting the
            // previous teardown, so a body scheduled inside that await sees a live session under
            // the run ID it captured (ProactiveQuickTests covers exactly this).
            guard !Task.isCancelled, self.isRunning, !self.isPreparing, self.proactiveEnabled else { return }
            await self.respondQuick(.proactive)
        }
    }

    /// Awaits an in-flight proactive fire and the Quick stream it started. Test hook — the app
    /// never needs to wait for an answer it did not ask for.
    func awaitProactiveFire() async {
        await proactiveTask?.value
        await waitForResponse(.quick)
    }

    // MARK: - On-demand responses (awaitable)

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
    /// charged with their speaker labels. With no window (Ollama, cloud) every block is kept whole.
    ///
    /// Which lines are sent is `OnDemandGrounding`'s choice (issue #114): the whole conversation when
    /// it fits; otherwise the Listener summary plus the most recent speech, or — with Auto off and no
    /// summary yet — the meeting's opening plus the most recent speech. The pane says which.
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
                                   personaGuidance: conversationPersona),
            action: action)
        // The provisional notice and an excerpt's note are part of the assembled prompt but invisible
        // to the scaffold probe, which measures with no messages. Both are charged up front, so
        // neither can be what pushes an Apple-sized prompt over its window.
        let notice = store.hasProvisionalSpeech ? PromptBuilder.provisionalNotice.count + 2 : 0
        let note = limit == nil ? 0 : OnDemandGrounding.promptNoteReserve
        let allocation = PromptBudget.allocate(
            limit: limit, scaffold: scaffold + notice + note,
            transcript: OnDemandGrounding.transcriptBudget(for: action, kind: kind, limit: limit),
            references: references.count, summary: summary.count, notes: notes.count)

        let (clampedReferences, droppedReferences) = Self.clamp(references, to: allocation.references)
        let (clampedSummary, droppedSummary) = Self.clamp(summary, to: allocation.summary)
        let (clampedNotes, droppedNotes) = Self.clamp(notes, to: allocation.notes)
        // Unfinalized speech may take at most half of the transcript allowance (issue #113); the
        // finalized lines get everything it does not actually use.
        let provisional = store.provisionalContext(maxChars: allocation.transcript / 2)
        let provisionalCost = provisional.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) }
        // The Listener summary stands in only for the leading lines its ledger says it read, and
        // only when it is whole: one cut off at the output limit or clamped to fit covers nothing
        // for sure, so it is sent but never claimed to cover anything.
        let covered = listenerSummaryCutOff || droppedSummary
            ? 0 : OnDemandGrounding.coveredPrefix(of: store.utterances, ids: summarizedSegmentIDs)
        let selection = OnDemandGrounding.select(store.utterances, budget: allocation.transcript - provisionalCost,
                                                 hasSummary: clampedSummary != nil, coveredCount: covered)
        pendingGrounding[role] = selection.notice(summaryName: "the Listener summary")
        // A context-window clamp is reported in the footer as well; the pane's grounding line says
        // which speech was kept, whatever the reason.
        promptTruncationNotice = limit == nil ? nil : PromptBudget.truncationNotice(
            transcriptDropped: selection.shape != .whole, referencesDropped: droppedReferences,
            auxiliaryDropped: droppedSummary || droppedNotes)
        return ContextEngine.context(
            messages: selection.segments + provisional, notes: clampedNotes, summary: clampedSummary,
            responseLanguage: responseLanguage, references: clampedReferences,
            personaGuidance: conversationPersona, transcriptNote: selection.promptNote)
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
        lastCompletedListenerSummary = ""; listenerSummaryCutOff = false
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
        deepAnswer = ""; clearRoleNotices()
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
                                       personaGuidance: self.listenerPersona),
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
                responseLanguage: self.responseLanguage, personaGuidance: self.listenerPersona))
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
        stoppedResponseText[role] = nil
        responseTasks[role]?.cancel()
        let generation = (responseGenerations[role] ?? 0) + 1
        responseGenerations[role] = generation
        pendingGrounding[role] = nil
        let request = makeRequest()
        let grounding = pendingGrounding[role]
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(role, request, generation: generation, grounding: grounding)
        }
        responseTasks[role] = task
        return task
    }

    private func run(_ role: CopilotRole, _ request: LLMRequest, generation: Int, grounding: String?) async {
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
        var cutOff = false
        defer {
            if generation == responseGenerations[role] {
                streamingRoles.remove(role)
                roleActivity[role] = nil
                pendingGrounding[role] = nil
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
                case .outputLimitReached:
                    // The text so far stays: it is a partial answer, and the pane says so (#215).
                    cutOff = true
                }
            }
            // Only a completed answer gets this request's notices; a failure keeps the previous
            // answer's record, which then describes the text restored below (or nothing).
            if generation == responseGenerations[role], !Task.isCancelled {
                roleNoticeRecords[role] = RoleNoticeRecord(text: output(role), grounding: grounding, cutOff: cutOff)
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
                listenerSummaryCutOff = cutOff
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
                // A refusal is the exception: its partial text is discarded, never left standing (#214).
                if output(role).isEmpty || LLMPartialOutput.mustDiscard(after: error) { setOutput(role, previousOutput) }
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

    func output(_ role: CopilotRole) -> String {
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
