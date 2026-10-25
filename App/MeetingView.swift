import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

struct MeetingView: View {
    /// Anchor id for keeping scroll views pinned to their newest content.
    static let scrollBottomID = "scroll-bottom"
    /// UserDefaults key for the Quick pane's "Proactive" toggle (answer Others' questions
    /// automatically). Absent = on, matching the documented default.
    static let proactiveDefaultsKey = "proactiveQuickAnswers"

    @State var session: MeetingSession
    @State var store: ConversationStore
    @State var startError: String?
    @State var showSettings = false
    @State private var permissions = PermissionsModel()
    @State private var showPermissions = false
    @State private var showOnboarding = false
    @State var restoredRecord: SessionRecord?
    @State var showSearch = false
    @State var sessionStore = SessionStore()
    /// Identity of this app-window's session. Reused across Listen→Stop cycles so repeated Stops
    /// upsert one growing record instead of writing a fresh superset each time.
    @State var currentSessionID = UUID().uuidString
    /// When the current conversation's first checkpoint was taken; the Save to folder note's date.
    @State var checkpointCoordinator = ConversationCheckpointCoordinator()
    var conversationStartedAt: Date? { checkpointCoordinator.startedAt }
    /// The languages this conversation was transcribed in, kept on its record (issue #206).
    @State var conversationLanguages = ConversationLanguages()
    /// `sessionSaveable`: whether this window-session may be persisted — tainted to false the
    /// moment saving is ever observed off (or history is cleared), so "turn off to keep nothing" holds
    /// for the whole session. `savingEnabledBeforeSettings`: toggle value snapshotted when Settings
    /// opened, so an off→on round-trip is still caught.
    @State var sessionSaveable = true
    @State private var savingEnabledBeforeSettings = true; @State var chatModels: [String] = []
    /// The discovered models whose `/api/show` metadata verifies them as local; handed to
    /// `ModelRanking.roleDefaults` so auto-defaults stay local-first (issue #137).
    @State var verifiedLocalModels: Set<String> = []
    @State var transcriptionLocaleID: String
    @State var presetID: String
    @State var vocabulary = SessionVocabulary()   // domain vocabularies and My terms (issue #222)
    @State var referencePaths: [URL]
    @State private var referenceLoadToken = 0
    @State var referenceSkipped: [TextFileReader.Skipped] = []
    @State var captureCoordinator = CaptureCoordinator()
    @State var importTask: Task<Void, Never>?
    @State var transcriptAtBottom = true
    /// User intent to be capturing — the toolbar button's source of truth. Stays true across the
    /// brief teardown window of a locale restart (when `session.isRunning` is transiently false),
    /// so a Stop press is never lost.
    var wantsCapture: Bool { captureCoordinator.wantsCapture }
    /// When the current recording run began, for the elapsed mm:ss timer. nil while idle.
    @State var recordingStartedAt: Date?
    /// Ticks while recording so the elapsed timer updates once per second.
    @State var now = Date()
    /// Live appearance (System/Light/Dark) applied to the root via `.preferredColorScheme`.
    @State private var appearance = ProviderSettings.appearance
    @State var othersAudioSink: SpeakerAudioBuffer
    @State var microphoneAudioSink: SpeakerAudioBuffer
    @State var showSpeakerBreakdown = false
    @State var speakerError: String?
    @State var speakerLoading = false
    @State var speakerParticipants: [SpeakerParticipant] = []
    @State var speakerTrackers: [SpeakerSource: SpeakerIdentityTracker] = [:]
    /// Cumulative diarized timeline per source, in stable identity-id space. Periodic passes analyze
    /// only a trailing window (issue #109) and are stitched onto this, so talk-time totals and
    /// per-line labels still cover the whole run without re-processing it.
    @State var speakerSegments: [SpeakerSource: [DiarizedSegment]] = [:]
    /// Every identity seen so far per source (id → name), including speakers absent from the newest
    /// window. Kept in step with `speakerTrackers` renames.
    @State var speakerIdentities: [SpeakerSource: [String: SpeakerIdentity]] = [:]
    /// How much of each sink a pass has already analyzed, so the next window starts there.
    @State var speakerAnalyzedSamples: [SpeakerSource: Int] = [:]
    /// One-line rail status (e.g. speaker models unavailable); nil when there is nothing to say.
    @State var speakerStatus: String?
    @State var speakerWork = SpeakerPassCoordinator()
    @State var nextSpeakerAnalysis = Date.distantFuture
    @State var diarizationRunStartIndex = 0
    @State var diarizationRunToken = 0
    @State var diarizationSinkAttached = false
    @State var microphoneSinkAttached = false
    @State var diarizationRunUsesTimestamps = false
    /// The transcription engine the live run was started with, or nil when idle. The transcriber is
    /// built once per run, so the rail must show this and not the (possibly just-changed) saved
    /// setting (issue #136).
    @State var activeEngine: String?
    @State var diarizer = SpeakerDiarizer()
    @State var modelStatus = ""
    @State private var modelLoadToken = 0
    @State private var showLicenses = false
    @State private var conversationTransitionBusy = false
    var lifecycleBusy: Bool {
        get { conversationTransitionBusy || (!wantsCapture && captureCoordinator.phase != .idle) }
        nonmutating set { conversationTransitionBusy = newValue }
    }
    @State var conversationTitle = ConversationTitle.generated(Date().formatted(date: .abbreviated, time: .shortened))
    /// Where the title came from, so an automatic name never replaces a typed one (#221).
    @State var conversationTitleState = ConversationTitleState.placeholder
    @State var titleCoordinator = ConversationTitleCoordinator()
    @FocusState var titleFieldFocused: Bool
    @State var saveMessage = "Not saved yet"
    @State var saveFailed = false
    private let hotkey = HotkeyMonitor()

    /// mm:ss since the current recording run started (00:00 when idle).
    var elapsedLabel: String { CommandCenterLabels.elapsed(since: recordingStartedAt, now: now) }

    /// SwiftUI color scheme for the stored appearance id; nil = follow the system.
    private func colorScheme(for id: String) -> ColorScheme? {
        switch id {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    init() {
        ProviderSettings.migratePinningIfNeeded()
        _transcriptionLocaleID = State(initialValue: ProviderSettings.transcriptionLocaleID)
        _presetID = State(initialValue: PresetCatalog.preset(id: ProviderSettings.presetID).id)
        let savedPaths = (UserDefaults.standard.array(forKey: "referencePaths") as? [String]) ?? []
        _referencePaths = State(initialValue: savedPaths.map { URL(fileURLWithPath: $0) })
        let store = ConversationStore()
        _store = State(initialValue: store)
        let othersSink = SpeakerAudioBuffer()
        _othersAudioSink = State(initialValue: othersSink)
        let microphoneSink = SpeakerAudioBuffer()
        _microphoneAudioSink = State(initialValue: microphoneSink)
        let savedAudioRuns = MacSavedAudio.shared.runs
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 8),
            makeCapture: {
                // Only accumulate the Others channel for diarization when the experimental setting
                // is on — otherwise a normal meeting needlessly resamples + retains up to ~2 h of
                // audio. Read at capture-creation time so toggling it before the next Listen applies.
                let diarize = ProviderSettings.speakerDiarizationEnabled
                // Always reset so a prior run's buffer is released even when the user has since
                // turned diarization off (otherwise the old ~2 h/~460 MB samples stay resident in
                // the @State-held sink). The reset also bumps the generation used below.
                othersSink.reset()
                microphoneSink.reset()
                // Capture the generation for THIS run right after the reset above. Any late append
                // from a prior run's capture carries an older generation and is rejected by the
                // buffer, so it can't contaminate this run. On the non-diarize path the sink is nil
                // and the value is unused.
                let gen = diarize ? othersSink.currentGeneration() : 0
                let identifyMic = diarize && ProviderSettings.microphoneDiarizationEnabled
                // Save audio recordings (#55): the conversation was chosen in `beginDiarizationRunReset`.
                // `MeetingSession.start` makes the capture on the main actor, after placing the recording.
                let saved = MainActor.assumeIsolated {
                    savedAudioRuns.writersForNewCapture(
                        timesMatchAudio: ProviderSettings.transcriptionEngine == "whisperKit")
                }
                return DualChannelCapture(othersSink: diarize ? othersSink : nil, sinkGeneration: gen,
                                          microphoneSink: identifyMic ? microphoneSink : nil,
                                          microphoneGeneration: microphoneSink.currentGeneration(),
                                          savedAudio: saved)
            },
            makeTranscriber: {
                let locale = ProviderSettings.transcriptionLocale()
                switch ProviderSettings.transcriptionEngine {
                case "speechRecognizer":
                    return SpeechRecognizerTranscriber(locale: locale) as any Transcribing
                case "whisperKit":
                    // "Auto" (empty id) → nil locale so WhisperKit auto-detects the language
                    // (enables multilingual / code-switching); an explicit pick forces that language.
                    let whisperLocale = ProviderSettings.transcriptionLocaleID.isEmpty
                        ? nil : ProviderSettings.transcriptionLocale()
                    return WhisperKitTranscriber(locale: whisperLocale) as any Transcribing
                default:
                    // Don't warm the system-audio analyzer when this process can't capture system
                    // audio: it would leave an idle analyzer + results task for the whole session
                    // (issue #147). `feed` still builds it lazily if system audio does arrive.
                    return SpeechAnalyzerTranscriber(
                        locale: locale,
                        warmSystemAudio: PermissionsModel.systemAudioLikelyAvailable()
                    ) as any Transcribing
                }
            },
            makeProvider: { Self.provider(model: $0) },
            models: [
                .listener: ProviderSettings.model(for: .listener),
                .quick: ProviderSettings.model(for: .quick),
                .deep: ProviderSettings.model(for: .deep)
            ],
            providerAvailability: { ProviderSettings.automaticReviewUnavailableReason(quickModel: $0) }
        )
        _session = State(initialValue: session)
        // Saved audio starts where the starting recording's lines start (#55; #233's recordingOffset).
        savedAudioRuns.timelineOffset = { [weak session] in session?.recordingOffset ?? 0 }
    }

    // MARK: - Ollama cloud routing

    /// The provider for `model` on the current AI route; also answers "Ask your history" (#57).
    nonisolated static func provider(model: String) -> any LLMProvider {
        if ProviderSettings.aiMode == .apple { return AppleIntelligenceProvider() as any LLMProvider }
        if ProviderSettings.aiMode == .openAI { return ProviderSettings.openAIProvider(model: model) }
        if ProviderSettings.aiMode == .cloudAI { return ProviderSettings.cloudAIProvider(model: model) }
        return OllamaProvider(model: model, baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey(),
                              localOnly: ProviderSettings.aiMode != .cloud)
    }

    nonisolated private static func ollamaKey() -> String? {
        guard ProviderSettings.aiMode == .cloud else { return nil }
        let k = KeychainStore.get("ollama")
        return (k?.isEmpty == false) ? k : nil
    }

    nonisolated private static func ollamaBaseURL() -> URL {
        ProviderSettings.aiMode == .cloud
            ? URL(string: "https://ollama.com")!
            : URL(string: "http://localhost:11434")!
    }

    /// True when the banner is showing a Calendar *denial*, the one calendar outcome the user can
    /// fix themselves. Derived from `startError` (like the microphone case just below it) so it can
    /// never disagree with the message on screen.
    private var calendarDenied: Bool { startError == CalendarLookup.denied.message }

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            topControlBar(session: session, showPermissions: $showPermissions)
            conversationStatus
            if !modelStatus.isEmpty && ProviderSettings.aiMode != .off {
                Text(modelStatus).font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
            }
            if let startError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("⚠️ \(startError)")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Only the denied case is fixable by the user in their own Privacy pane; a
                    // restricted (managed) Mac gets the explanation without a dead-end button.
                    if startError == CapturePreflight.deniedMessage {
                        Button("Open Settings") { permissions.openSettings("Privacy_Microphone") }
                    }
                    // Calendar denial is equally fixable, and had no button at all (issue #136).
                    if calendarDenied {
                        Button("Open Calendar privacy settings") {
                            permissions.openSettings("Privacy_Calendars")
                        }
                    }
                    // The banner is shared by start, import, export and calendar failures and used
                    // to clear only on the next start — so a stale export error sat above a live
                    // recording with no way to get rid of it (issue #136).
                    Button { self.startError = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss this message")
                    .accessibilityLabel("Dismiss message")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .background(Theme.windowBackground)
            }
            MacVocabularyBanner(vocabulary: vocabulary, conversationID: currentSessionID, apply: applyVocabulary)
            // HSplitView so the user can drag the rail/transcript/copilot dividers; each column
            // carries its own min/ideal/max width so the handles have room to move.
            HSplitView {
                statusRail(session: session)
                transcriptColumn(session: session, notes: $session.notes)
                copilotColumn(session: session)
            }
            .frame(maxHeight: .infinity)
            CommandCenterFooter(mode: ProviderSettings.aiMode)
        }
        .background(Theme.windowBackground)
        .preferredColorScheme(colorScheme(for: appearance))
        .frame(minWidth: 1100, minHeight: 560)
        // Tick the elapsed timer once per second while recording.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            if recordingStartedAt != nil { now = date }
            if !saveFailed { _ = checkpoint(complete: !wantsCapture && !lifecycleBusy && !session.isTranscribingFile) }
            // Not while preparing: the session is "running" from Start, but no audio has reached the
            // diarization sink yet, so an analysis here would run against the previous run's
            // leftovers (or nothing at all) — the same reason automatic reviews are gated (#147).
            if wantsCapture && session.isRunning && !session.isPreparing && date >= nextSpeakerAnalysis {
                identifySpeakers(showSheet: false)
            }
        }
        .onChange(of: store.revision) { _, _ in _ = checkpoint(); considerVocabularySuggestion() }
        .onChange(of: currentSessionID) { _, _ in applyVocabulary() }
        .sheet(isPresented: $showSettings, onDismiss: {
            session.aiEnabled = ProviderSettings.aiMode != .off
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            appearance = ProviderSettings.appearance   // apply an appearance change live
            vocabulary.reloadSettings(); applyVocabulary()
            // Rebuild attached references so a changed reference-budget takes effect immediately.
            if !referencePaths.isEmpty { loadReferences(into: session) }
            markSaveableAfterSettings(); Task { await reloadAndHealModels() }
        }, content: {
            SettingsView()
        })
        .sheet(isPresented: $showPermissions) {
            PermissionsView(permissions: permissions)
        }
        .sheet(isPresented: $showLicenses) {
            VStack {
                Text("Open-source licenses").font(.title2)
                ScrollView {
                    Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt").flatMap {
                        try? String(contentsOf: $0, encoding: .utf8)
                    } ?? "Notices are unavailable in this build.")
                        .font(.body).textSelection(.enabled).padding()
                }
                Button("Done") { showLicenses = false }
            }.padding().frame(width: 700, height: 560)
        }
        .sheet(isPresented: $showSearch) {
            SessionSearchView(store: sessionStore, onClear: { dropCurrentSessionFromSaving() },
                              onOpen: { openConversation($0) }, askRoute: { Self.historyAskRoute() })
        }
        .sheet(isPresented: $showSpeakerBreakdown) {
            SpeakerBreakdownView(
                loading: speakerLoading, participants: speakerParticipants, errorText: speakerError,
                didTruncate: othersAudioSink.didTruncate || microphoneAudioSink.didTruncate,
                perLineLabelsUnavailable: !diarizationRunUsesTimestamps,
                onRename: renameSpeaker)
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            // Onboarding may have set/cleared the Ollama key, which changes the route; rebuild
            // every role's provider so the panes use the new local/cloud configuration.
            Task { await reloadAndHealModels() }
        }, content: {
            OnboardingView()
        })
        .onAppear {
            session.autoSummaryEnabled = UserDefaults.standard.bool(forKey: "autoQuickSummary")
            // Proactive answers default ON (README/smoke test): absent a stored choice, keep them on.
            session.proactiveEnabled = UserDefaults.standard.object(forKey: Self.proactiveDefaultsKey) as? Bool ?? true
            session.aiEnabled = ProviderSettings.aiMode != .off
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            applyVocabulary()   // the preset persona, the vocabularies' guidance and recognition terms
            ApplicationLifecycle.shared.prepareToClose = { await prepareToClose() }
            if !referencePaths.isEmpty { loadReferences(into: session) }
            hotkey.start { Task { await session.respondQuick(.answerQuestion) } }
            permissions.refresh()
            // Setup appears once. Inconclusive permission checks must not reopen a modal on
            // every launch; permissions remain available explicitly from More.
            if !UserDefaults.standard.bool(forKey: OnboardingView.completionKey) {
                showOnboarding = true
            }
        }
        .task {
            retryVaultNotesAtLaunch()
            // Saved audio (#55): runs the app was killed in are repaired, audio with no conversation goes.
            MacSavedAudio.shared.tidy(keeping: sessionStore.completeIDs())
            await reloadAndHealModels()
        }
        .background(WindowCloseHandler())
        .focusedSceneValue(\.conversationCommands, conversationCommands)
        .onDisappear { tearDownOnDisappear(session: session) }
    }

}

extension MeetingView {
    // MARK: - Top control bar

    /// Replaces the old icon-row toolbar: Listen/Stop + pulsing indicator + elapsed timer on the
    /// left; the same icon actions that existed before on the right (refresh-models, import audio,
    /// export menu, copy-session, search, permissions, settings).
    private func topControlBar(session: MeetingSession, showPermissions: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Button { toggleCapture(session: session) } label: {
                Label(wantsCapture ? "Stop listening" : "Start listening", systemImage: wantsCapture ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Start or stop capturing microphone and system audio")
            .disabled(lifecycleBusy || session.isTranscribingFile)
            Button { saveConversation() } label: { Label("Save conversation", systemImage: "square.and.arrow.down") }
                .disabled(!hasConversation)
                .help("Save without stopping capture (Command-S)")
            Button { newConversation() } label: { Label("New conversation", systemImage: "plus") }
                .disabled(lifecycleBusy || session.isTranscribingFile)
                .help("Save this conversation, then start a clean one (Command-N)")
            Button { showSearch = true } label: { Label("History", systemImage: "clock") }
                .help("Open saved conversations (Command-F)")
            Menu {
                ConversationExportMenu(record: { currentRecord(date: conversationStartedAt ?? Date()) },
                                       hasTimestamps: TranscriptTimestamp.hasTimes(store.utterances),
                                       onError: { startError = $0 })
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .help("Export or copy this conversation")
            Button { openSettings($showSettings) } label: { Label("Settings", systemImage: "gearshape") }
                .help("Configure transcription, AI, and saving (Command-comma)")
            Menu {
                Button("Refresh models") { Task { await reloadAndHealModels() } }
                Button("Import audio file…") { importAudioFile(session: session) }
                    .disabled(wantsCapture || lifecycleBusy || session.isTranscribingFile)
                Button("Permissions…") { showPermissions.wrappedValue = true }
                Button("Open-source licenses…") { showLicenses = true }
            } label: { Label("More", systemImage: "ellipsis") }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .controlSize(.large)
        .imageScale(.large)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.windowBackground)
    }

    /// Listen pre-flight for microphone authorization (issue #110). Returns true when capture may
    /// start; otherwise sets `startError` (the banner offers Open Settings when the user can fix it
    /// themselves) and leaves the session stopped rather than recording silence.
    func ensureMicrophoneAccess() async -> Bool {
        var decision = CapturePreflight.decide(microphone: PermissionsModel.currentMicrophoneAuthorization())
        if decision == .requestAccess {
            let granted = await PermissionsModel.requestMicrophoneAccess()
            permissions.refresh()
            decision = CapturePreflight.decideAfterRequest(granted: granted)
        }
        if case .blocked(let message, _) = decision {
            startError = message
            return false
        }
        return true
    }

    /// Pre-start half of a diarization-run reset: clear stale inline labels and bump the run token so
    /// any in-flight `identifySpeakers` drops its (now stale) results. Call this BEFORE `session.start()`
    /// — the run anchor is set only AFTER start returns (see `anchorDiarizationRun`), because
    /// `start()` awaits the prior Stop's drain, which can still append old final utterances first.
    ///
    /// Also release the breakdown UI: bumping the token makes a superseded `identifySpeakers` task
    /// bail via its token guard WITHOUT clearing `speakerLoading`, so we clear the spinner/error state
    /// here. This guarantees that starting/restarting always frees the "Identify speakers" button.
    func beginDiarizationRunReset() {
        speakerWork.cancel()
        let run = diarizationRunToken + 1
        let remotePrefix = run == 1 ? "Speaker" : "Run \(run) speaker"
        let micPrefix = run == 1 ? "Mic speaker" : "Run \(run) mic speaker"
        speakerTrackers = [.others: SpeakerIdentityTracker(prefix: remotePrefix),
                           .you: SpeakerIdentityTracker(prefix: micPrefix)]
        speakerParticipants = []
        speakerSegments = [:]
        speakerIdentities = [:]
        speakerAnalyzedSamples = [:]
        speakerStatus = nil
        // A new recording is also a retry: the model download may well succeed now (#109).
        Task { await diarizer.retryModelLoad() }
        nextSpeakerAnalysis = .distantFuture
        speakerLoading = false
        speakerError = nil
        diarizationRunToken &+= 1
        // Every capture start passes here first: the next capture saves its audio into this conversation.
        // Audio only for a conversation History will keep (#55 review): none while autosaving is off.
        MacSavedAudio.shared.prepareRun(conversationID: ProviderSettings.saveSessionsForSearch && sessionSaveable
                                        ? currentSessionID : nil)
        // Disable Identify for the whole transition window: `session.start()` first awaits the prior
        // Stop's drain, then `makeCapture` calls `othersSink.reset()`. Until that reset+attach happens
        // the buffer still holds the PREVIOUS run's audio under the new token, so an Identify here
        // would slip a stale result past the token guard. We re-enable in `anchorDiarizationRun()`,
        // once start() has returned and the new run is fully live. The run snapshots are also taken
        // there (not here), so they reflect what the new capture/transcriber actually used.
        diarizationSinkAttached = false
        microphoneSinkAttached = false
    }

    /// Post-start half: anchor diarization to the current run and snapshot what it actually used. By
    /// the time `session.start()` returns, the previous run's drain is complete (its finals are in the
    /// store) and the new capture has reset+attached the sink, so `store.utterances.count` marks where
    /// this run's lines begin and the live settings match the capture/transcriber just built.
    func anchorDiarizationRun() {
        diarizationRunStartIndex = store.utterances.count
        MacSavedAudio.shared.anchorRun(firstSegment: store.utterances.count)
        // Snapshot the settings the new run's capture/transcriber were built from. `makeCapture` read
        // `speakerDiarizationEnabled` to decide sink attachment and `makeTranscriber` read the engine,
        // both during the `start()` that just returned — so reading them now matches this run, and
        // re-enables Identify only when the sink is actually attached and live.
        diarizationSinkAttached = ProviderSettings.speakerDiarizationEnabled
        diarizationRunUsesTimestamps = ProviderSettings.transcriptionEngine == "whisperKit"
        microphoneSinkAttached = diarizationSinkAttached && ProviderSettings.microphoneDiarizationEnabled
        nextSpeakerAnalysis = Date().addingTimeInterval(SpeakerAnalysisPolicy.minimumRest)
    }

    /// Attach/clear files & folders whose text is fed into Quick/Deep prompts as grounding.
    func referenceFilesRow(session: MeetingSession) -> some View {
        HStack(spacing: 8) {
            Button { addReferenceFiles(session: session) } label: {
                Label("Add files / folders", systemImage: "paperclip")
            }
            .help("Attach local files or folders as reference context for Quick & Deep answers")
            if !referencePaths.isEmpty {
                Text(referenceSummary)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !referenceSkipped.isEmpty {
                    Label(referenceSkippedSummary, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).lineLimit(1)
                        .help(referenceSkippedDetail)
                }
                Button("Clear") { clearReferences(session: session) }
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    var referenceSummary: String {
        let names = referencePaths.map { $0.lastPathComponent }
        let shown = names.prefix(2).joined(separator: ", ")
        return referencePaths.count > 2 ? "\(shown) +\(referencePaths.count - 2) more" : shown
    }

    /// One-line "not included" status so a file the model never saw is never invisible.
    var referenceSkippedSummary: String {
        guard let first = referenceSkipped.first else { return "" }
        return referenceSkipped.count == 1
            ? "Not included: \(first.name) (\(first.reason))"
            : "\(referenceSkipped.count) files not included"
    }

    var referenceSkippedDetail: String {
        "Not included in reference context:\n"
            + referenceSkipped.map { "• \($0.name) — \($0.reason)" }.joined(separator: "\n")
    }

    func addReferenceFiles(session: MeetingSession) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders to use as reference context"
        guard panel.runModal() == .OK else { return }
        // De-duplicate by standardized path while preserving order.
        var seen = Set(referencePaths.map { $0.standardizedFileURL.path })
        for url in panel.urls where seen.insert(url.standardizedFileURL.path).inserted {
            referencePaths.append(url)
        }
        persistReferencePaths()
        loadReferences(into: session)
    }

    func clearReferences(session: MeetingSession) {
        referencePaths = []
        referenceSkipped = []
        referenceLoadToken += 1   // supersede any in-flight load so it can't reapply old files
        persistReferencePaths()
        session.referenceContext = nil
    }

    private func persistReferencePaths() {
        UserDefaults.standard.set(referencePaths.map(\.path), forKey: "referencePaths")
    }

    /// Reads the attached files/folders off the main actor and updates the session's grounding.
    private func loadReferences(into session: MeetingSession) {
        referenceLoadToken += 1
        let token = referenceLoadToken
        let urls = referencePaths
        Task {
            let loaded = await Task.detached { FileContextLoader.load(urls) }.value
            guard token == referenceLoadToken else { return }   // superseded by a newer add/clear
            referenceSkipped = loaded.skipped
            session.referenceContext = ReferenceBuilder.build(
                documents: loaded.documents,
                maxChars: ProviderSettings.referenceBudget
            )
        }
    }

}

// MARK: - Actions (import / export / model refresh)

extension MeetingView {
    /// Imports an audio file and transcribes it into the Transcript pane (labeled "Others"),
    /// using the currently-selected language. Independent of live recording.
    func importAudioFile(session: MeetingSession) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose an audio file to transcribe"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let producer = AudioFileChunkProducer(url: url, source: .others) else {
            startError = "Couldn't read that audio file."
            return
        }
        startError = nil
        // Imports always use SpeechAnalyzer (it finalizes all fed audio, so fast-feeding a file is
        // lossless), regardless of the live-capture engine setting; the chosen language still applies.
        let locale = ProviderSettings.transcriptionLocale()
        noteCaptureLanguage(engine: "speechAnalyzer")
        importTask?.cancel()
        importTask = Task {
            await session.transcribeAudio(
                nextChunk: { await producer.next() },
                transcriber: { SpeechAnalyzerTranscriber(locale: locale) as any Transcribing })
        }
    }

    /// Pre-fills the Context-notes field from the user's current or next calendar meeting.
    /// Calendar access is async, so this runs on a Task; failures degrade to an inline message.
    func loadFromCalendar(session: MeetingSession) {
        startError = nil
        Task {
            let lookup = await CalendarService.currentOrNextMeeting()
            guard case .meeting(let info) = lookup else {
                startError = lookup.message
                return
            }
            session.notes = MeetingContext.notes(
                for: info,
                timeFormat: { $0.formatted(date: .omitted, time: .shortened) })
            // Title the conversation after the meeting — History, exports and the window all showed
            // "Conversation — <date>" even though the app knew the real name (issue #136). Only the
            // generated title is replaced, so a title the user typed is never clobbered.
            // An automatic name (#221) is replaced too: the meeting's own name is better.
            if ConversationAutoTitle.calendarMayReplace(state: conversationTitleState, title: conversationTitle),
               !info.title.isEmpty {
                conversationTitle = info.title
                conversationTitleState = .calendar   // never renamed automatically (#221)
            }
        }
    }

    /// Window close/teardown: stop the hotkey and any pending restart/import. If recording, mirror
    /// the Stop-button flow so a meeting ended by closing the window is still saved for search
    /// (best-effort: the Task may not finish on a full app quit).
    func tearDownOnDisappear(session: MeetingSession) {
        hotkey.stop()
        for role in CopilotRole.allCases { session.cancelResponse(role) }
        speakerWork.cancel()
        diarizationRunToken &+= 1
        let wasCapturing = wantsCapture
        importTask?.cancel()    // stop an in-flight file import when the window closes
        if wasCapturing {
            _ = checkpoint()
            captureCoordinator.requestStop(after: {
                _ = checkpoint(complete: true, force: true)
            })
        } else {
            captureCoordinator.requestStop()
            session.stop()
        }
    }

    /// Opens Settings, snapshotting the saving toggle first so an off→on round-trip is still caught
    /// on dismiss (see `markSaveableAfterSettings`).
    func openSettings(_ showSettings: Binding<Bool>) {
        savingEnabledBeforeSettings = ProviderSettings.saveSessionsForSearch
        showSettings.wrappedValue = true
    }

    /// Settings-dismiss: taint the session only when saving was off at some point during the visit
    /// (off when opened OR off now) AND content was already captured — that content was at risk, so
    /// exclude the whole window-session. Turning saving ON before recording anything leaves it
    /// untainted, so saving works normally for that window.
    func markSaveableAfterSettings() {
        let wasOff = !savingEnabledBeforeSettings || !ProviderSettings.saveSessionsForSearch
        // "Has content" includes an in-progress partial, so audio captured mid-utterance while
        // saving was off still taints the session.
        let hasContent = !store.utterances.isEmpty || store.partial != nil
        if wasOff && hasContent { sessionSaveable = false }
    }

    /// Drops the current in-memory session from future saves after the user clears history, so a
    /// just-deleted transcript can't be re-persisted. A fresh id starts a new (still untainted)
    /// upsert key once this session is sealed.
    func dropCurrentSessionFromSaving() {
        // Only taint when the current window-session has content that was just cleared — clearing
        // old records on a fresh/empty window must not silently disable future saving.
        if hasConversation { sessionSaveable = false }
        currentSessionID = UUID().uuidString
        vocabulary.restore(domainIDs: nil, for: currentSessionID, transcriptLineCount: store.utterances.count)
        applyVocabulary()
        checkpointCoordinator.reset()
    }

    /// On Stop, persist the finished session for cross-meeting search when this window-session is
    /// saveable (saving never observed off), saving is on, and there's new transcript. Reuses
    /// `currentSessionID` so repeated Listen→Stop cycles upsert one growing record. Title = the
    /// active preset's name (or "Session") plus the date.
    func saveSessionIfEnabled(session: MeetingSession, force: Bool = false) {
        _ = checkpoint(complete: !wantsCapture && !lifecycleBusy, force: force)
    }

    /// Reloads the installed Ollama chat models into the per-pane pickers.
    func reloadModels() async {
        if ProviderSettings.aiMode == .apple {
            chatModels = ["Apple Intelligence"]; verifiedLocalModels = []; return
        }
        let discovered = await Self.discoverChatModels()
        chatModels = discovered.names
        verifiedLocalModels = discovered.verifiedLocal
    }

    /// Reloads chat models for the current Ollama route (cloud vs local) and heals each role:
    /// keep the current model if it exists on the new route, otherwise fall back to a
    /// role-appropriate default (Quick = lightest, Deep = heaviest, Listener = balanced).
    /// Always rebuilds every role's provider so it picks up the current base URL/key.
    func reloadAndHealModels() async {
        session.aiEnabled = ProviderSettings.aiMode != .off
        // Cancel old-route work immediately, before asynchronous discovery can suspend this task.
        for role in CopilotRole.allCases { session.setModel(role, session.models[role] ?? "") }
        modelLoadToken += 1
        let token = modelLoadToken
        if ProviderSettings.aiMode == .apple {
            chatModels = ["Apple Intelligence"]
            verifiedLocalModels = []
            modelStatus = AppleIntelligenceProvider.unavailableReason ?? ""
            for role in CopilotRole.allCases { session.setModel(role, "Apple Intelligence") }
            return
        }
        let discovered = await Self.discoverChatModels()
        guard token == modelLoadToken else { return }
        chatModels = discovered.names
        verifiedLocalModels = discovered.verifiedLocal
        modelStatus = ProviderSettings.aiMode == .off ? "AI is off" : (chatModels.isEmpty
            ? (discovered.problem ?? "No available AI models. Check Ollama and AI mode in Settings, then Refresh models.") : "")
        // Locality comes from Ollama's own /api/show metadata, never from the model's name, so an
        // unpinned pane can never be auto-assigned a cloud model while a local one exists (#137).
        // An OpenAI-compatible catalog is never auto-assigned from (#52): see PaneModelHealing.
        // Nor is a cloud AI service's list (#214): the user picks every pane's model.
        let autoAssign = ProviderSettings.aiMode != .openAI && ProviderSettings.aiMode != .cloudAI
        let defaults = autoAssign ? ModelRanking.roleDefaults(from: chatModels, local: verifiedLocalModels) : [:]
        for role in CopilotRole.allCases {
            let current = ProviderSettings.model(for: role)
            let decision = PaneModelHealing.decide(current: current, pinned: ProviderSettings.isPinned(role),
                                                   available: chatModels, fallback: defaults[role],
                                                   autoAssign: autoAssign)
            if decision.persist { ProviderSettings.setModel(decision.model, for: role) }
            session.setModel(role, decision.model)   // rebuild the provider so it picks up the new base URL/key
        }
        if !autoAssign, !chatModels.isEmpty, CopilotRole.allCases.contains(where: { session.models[$0]?.isEmpty ?? true }) {
            modelStatus = "Choose a model for each pane in the status rail. ListenToMe never picks one "
                + "from \(ProviderSettings.aiMode == .cloudAI ? "a cloud AI service's" : "an OpenAI-compatible server's") "
                + "list for you."
        }
    }
}

extension MeetingView {
    /// Chat models on the selected route: Ollama's `/api/tags` + `/api/show`, or an OpenAI-compatible
    /// server's `/v1/models` (issue #52), whose models are never treated as verified local.
    nonisolated static func discoverChatModels() async -> OllamaModels.Discovery {
        if ProviderSettings.aiMode == .openAI { return await OpenAICompatibleModels.discover() }
        if ProviderSettings.aiMode == .cloudAI { return await CloudAIModels.discover() }
        return await OllamaModels.chatModels(
            baseURL: ollamaBaseURL(), apiKey: ollamaKey(), localOnly: ProviderSettings.aiMode != .cloud)
    }
}
