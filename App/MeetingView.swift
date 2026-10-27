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

    @State var suggestedMeeting: MeetingInfo?
    @State var calendarContext = CalendarContextCoordinator()
    @State var closeCoordinator = ConversationCloseCoordinator()
    @State var newCoordinator = NewConversationCoordinator()
    @State var meetingSuggestionPolicy = MeetingSuggestionPolicy()
    @State var nextMeetingPoll = Date.distantPast
    @State var session: MeetingSession
    @State var store: ConversationStore
    @State var operationErrors = MacOperationErrors()
    var startError: String? {
        get { operationErrors.capture }
        nonmutating set { operationErrors.capture = newValue }
    }
    @State var recordingAvailability: FeatureAvailability = .temporarilyUnavailable(reason: "Checking recording support…")
    @State var capabilityWork = LatestResultCoordinator<FeatureAvailability>()
    @State var calendarSuggestionWork = LatestResultCoordinator<CalendarLookup>()
    @State var speakerModelReset = LatestResultCoordinator<Void>()
    @State var speakerCheckpoint = LatestResultCoordinator<Void>()
    @State var captureStartGate = CaptureStartGate()
    var exportError: String? {
        get { operationErrors.file }
        nonmutating set { operationErrors.file = newValue }
    }
    @State var showSettings = false
    @State var permissions = PermissionsModel()
    @State var showPermissions = false
    @State private var showOnboarding = false
    @State var restoredRecord: SessionRecord?
    @State var showSearch = false
    @State var showRetranscription = false
    @State var sessionStore = SessionStore()
    /// Identity of this app-window's session. Reused across Listen→Stop cycles so repeated Stops
    /// upsert one growing record instead of writing a fresh superset each time.
    @State var currentSessionID = UUID().uuidString
    /// When the current conversation's first checkpoint was taken; the Save to folder note's date.
    @State var checkpointController = MacCheckpointController()
    var checkpointCoordinator: ConversationCheckpointCoordinator { checkpointController.coordinator }
    var conversationStartedAt: Date? { checkpointCoordinator.startedAt }
    /// The languages this conversation was transcribed in, kept on its record (issue #206).
    @State var conversationLanguages = ConversationLanguages()
    /// `sessionSaveable`: whether this window-session may be persisted — tainted to false the
    /// moment saving is ever observed off (or history is cleared), so "turn off to keep nothing" holds
    /// for the whole session. `savingEnabledBeforeSettings`: toggle value snapshotted when Settings
    /// opened, so an off→on round-trip is still caught.
    @State var sessionSaveable = true
    @State var savingEnabledBeforeSettings = true; @State var chatModels: [String] = []
    /// The discovered models whose `/api/show` metadata verifies them as local; handed to
    /// `ModelRanking.roleDefaults` so auto-defaults stay local-first (issue #137).
    @State var verifiedLocalModels: Set<String> = []
    @State var transcriptionLocaleID: String
    @State var presetID: String
    @State var vocabulary = SessionVocabulary()   // domain vocabularies and My terms (issue #222)
    @State var referencePaths: [URL]
    @State var referenceContext = ReferenceContextCoordinator()
    @State var referenceSkipped: [TextFileReader.Skipped] = []
    @State var referenceAccessWarnings: [TextFileReader.Skipped] = []
    @State var captureCoordinator = CaptureCoordinator()
    @State var importWork = FileImportCoordinator()
    @State var importStatus = AudioImportStatus()
    var isImporting: Bool { importWork.isActive || session.isTranscribingFile }
    @State var transcriptFollow = TranscriptFollowState()
    @State var transcriptScrollWork = LatestResultCoordinator<Void>()
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
    @State var localOllamaReadiness: LocalOllamaReadiness?
    @State var modelCatalog = ModelCatalogCoordinator()
    @State var showLicenses = false
    @State private var conversationTransitionBusy = false
    var lifecycleBusy: Bool {
        get { newCoordinator.isBusy || conversationTransitionBusy || (!wantsCapture && captureCoordinator.phase != .idle) }
        nonmutating set { conversationTransitionBusy = newValue }
    }
    @State var conversationTitle = ConversationTitle.generated(Date().formatted(date: .abbreviated, time: .shortened))
    /// Where the title came from, so an automatic name never replaces a typed one (#221).
    @State var conversationTitleState = ConversationTitleState.placeholder
    @State var titleCoordinator = ConversationTitleCoordinator()
    @FocusState var titleFieldFocused: Bool
    var saveMessage: String {
        get { checkpointController.message }
        nonmutating set { checkpointController.message = newValue }
    }
    var saveFailed: Bool {
        get { checkpointController.failed }
        nonmutating set { checkpointController.failed = newValue }
    }
    var lastSavedKey: SessionCheckpointKey? { checkpointCoordinator.lastSavedKey }
    @State var hotkey = HotkeyMonitor()

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
        let references = ReferenceSelectionStore().restore()
        _referencePaths = State(initialValue: references.urls)
        _referenceSkipped = State(initialValue: references.skipped)
        _referenceAccessWarnings = State(initialValue: references.skipped)
        let environment = MacMeetingEnvironment.configured()
        _store = State(initialValue: environment.store)
        _session = State(initialValue: environment.session)
        _othersAudioSink = State(initialValue: environment.othersSink)
        _microphoneAudioSink = State(initialValue: environment.microphoneSink)
    }

    var body: some View {
        return workspaceContent
        .background(Theme.windowBackground)
        .preferredColorScheme(colorScheme(for: appearance))
        .frame(minWidth: 1100, minHeight: 560)
        // Tick the elapsed timer once per second while recording.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            pollMeetingSuggestion(now: date)
            if recordingStartedAt != nil { now = date }
            if !saveFailed { _ = checkpoint(complete: !wantsCapture && !lifecycleBusy && !isImporting) }
            // Not while preparing: the session is "running" from Start, but no audio has reached the
            // diarization sink yet, so an analysis here would run against the previous run's
            // leftovers (or nothing at all) — the same reason automatic reviews are gated (#147).
            if wantsCapture && session.isRunning && !session.isPreparing && date >= nextSpeakerAnalysis {
                identifySpeakers(showSheet: false)
            }
        }
        .sheet(isPresented: $showRetranscription) { retranscriptionSheet }
        .onChange(of: store.revision) { _, _ in _ = checkpoint(); considerVocabularySuggestion() }
        .onChange(of: session.languageOptions) { _, _ in _ = checkpoint() }
        .onChange(of: currentSessionID) { _, _ in applyVocabulary() }
        .onChange(of: store.revision) { _, _ in session.updateLiveTranslations() }
        .sheet(isPresented: $showSettings, onDismiss: {
            session.aiEnabled = MacFeatureReadiness.aiCanRun(mode: ProviderSettings.aiMode,
            appleReason: MacDeviceCapabilities.appleReason(locale: currentCapabilityLocale))
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            appearance = ProviderSettings.appearance   // apply an appearance change live
            vocabulary.reloadSettings(); applyVocabulary()
            // Rebuild attached references so a changed reference-budget takes effect immediately.
            if !referencePaths.isEmpty { loadReferences(into: session) }
            markSaveableAfterSettings()
            requestModelRefresh()
            requestFeatureRefresh()
        }, content: {
            SettingsView()
        })
        .sheet(isPresented: $showPermissions, onDismiss: { requestFeatureRefresh() }) {
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
                              onDelete: { id in
                                  if id == currentSessionID { dropCurrentSessionFromSaving() }
                              },
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
            requestModelRefresh()
        }, content: {
            OnboardingView()
        })
        .safeAreaInset(edge: .bottom) {
            if let message = hotkey.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
        .onAppear {
            session.setTranslationSuspended(false)
            captureStartGate.reopen()
            session.structuredListenerEnabled = true
            session.autoSummaryEnabled = UserDefaults.standard.bool(forKey: "autoQuickSummary")
            // Proactive answers default ON (README/smoke test): absent a stored choice, keep them on.
            session.proactiveEnabled = UserDefaults.standard.object(forKey: Self.proactiveDefaultsKey) as? Bool ?? true
            session.aiEnabled = MacFeatureReadiness.aiCanRun(mode: ProviderSettings.aiMode,
            appleReason: MacDeviceCapabilities.appleReason(locale: currentCapabilityLocale))
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            applyVocabulary()   // the preset persona, the vocabularies' guidance and recognition terms
            ApplicationLifecycle.shared.prepareToClose = { await prepareToClose() }
            if !referencePaths.isEmpty { loadReferences(into: session) }
            hotkey.start { session.requestQuick(.answerQuestion) }
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
        .task(id: transcriptionLocaleID) { await refreshFeatureAvailability() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            requestFeatureRefresh()
        }
        .background(WindowCloseHandler())
        .focusedSceneValue(\.conversationCommands, conversationCommands)
        .onDisappear { tearDownOnDisappear(session: session) }
    }

}
