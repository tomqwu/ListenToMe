import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

struct MeetingView: View {
    /// Anchor id for keeping scroll views pinned to their newest content.
    static let scrollBottomID = "scroll-bottom"

    @State var session: MeetingSession
    @State var store: ConversationStore
    @State var startError: String?
    @State var showSettings = false
    @State private var permissions = PermissionsModel()
    @State private var showPermissions = false
    @State private var showOnboarding = false
    @State var showSearch = false
    @State var sessionStore = SessionStore()
    /// Identity of this app-window's session. Reused across Listen→Stop cycles so repeated Stops
    /// upsert one growing record instead of writing a fresh superset each time.
    @State var currentSessionID = UUID().uuidString
    /// `lastSavedUtteranceCount`: count at the last save, so an unchanged transcript isn't re-saved on
    /// Stop. `sessionSaveable`: whether this window-session may be persisted — tainted to false the
    /// moment saving is ever observed off (or history is cleared), so "turn off to keep nothing" holds
    /// for the whole session. `savingEnabledBeforeSettings`: toggle value snapshotted when Settings
    /// opened, so an off→on round-trip is still caught.
    @State var sessionSaveable = true
    @State private var savingEnabledBeforeSettings = true; @State var chatModels: [String] = []
    @State var transcriptionLocaleID: String
    @State var presetID: String
    @State var referencePaths: [URL]
    @State private var referenceLoadToken = 0
    @State var restartTask: Task<Void, Never>?
    @State var importTask: Task<Void, Never>?
    @State var transcriptAtBottom = true
    /// User intent to be capturing — the toolbar button's source of truth. Stays true across the
    /// brief teardown window of a locale restart (when `session.isRunning` is transiently false),
    /// so a Stop press is never lost.
    @State var wantsCapture = false
    /// When the current recording run began, for the elapsed mm:ss timer. nil while idle.
    @State var recordingStartedAt: Date?
    /// Ticks while recording so the elapsed timer updates once per second.
    @State private var now = Date()
    /// Live appearance (System/Light/Dark) applied to the root via `.preferredColorScheme`.
    @State private var appearance = ProviderSettings.appearance
    @State var othersAudioSink: SpeakerAudioBuffer
    @State var microphoneAudioSink: SpeakerAudioBuffer
    @State var showSpeakerBreakdown = false
    @State var speakerError: String?
    @State var speakerLoading = false
    @State var speakerParticipants: [SpeakerParticipant] = []
    @State var speakerTrackers: [SpeakerSource: SpeakerIdentityTracker] = [:]
    @State var speakerTask: Task<Void, Never>?
    @State var nextSpeakerAnalysis = Date.distantFuture
    @State var diarizationRunStartIndex = 0
    @State var diarizationRunToken = 0
    @State var diarizationSinkAttached = false
    @State var microphoneSinkAttached = false
    @State var diarizationRunUsesTimestamps = false
    @State var diarizer = SpeakerDiarizer()
    @State var modelStatus = ""
    @State private var modelLoadToken = 0
    @State private var showLicenses = false
    @State var lifecycleBusy = false
    @State var conversationTitle = "Conversation — " + Date().formatted(date: .abbreviated, time: .shortened)
    @State var saveMessage = "Not saved yet"
    @State var saveFailed = false
    @State var lastSavedSignature = ""
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

    /// Curated transcription languages. "" = follow the system language ("Auto"). Apple's
    /// on-device Speech selects one primary language; it does not auto-detect or code-switch.
    static let languageOptions: [(id: String, label: String)] = [
        ("", "Auto (system)"),
        ("en-US", "English (US)"),
        ("zh-CN", "中文 · Mandarin (简体)"),
        ("zh-TW", "中文 · Mandarin (繁體)"),
        ("yue-CN", "粵語 · Cantonese"),
        ("ja-JP", "日本語"),
        ("ko-KR", "한국어"),
        ("es-ES", "Español"),
        ("fr-FR", "Français"),
        ("de-DE", "Deutsch")
    ]

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
        _session = State(initialValue: MeetingSession(
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
                return DualChannelCapture(othersSink: diarize ? othersSink : nil, sinkGeneration: gen,
                                          microphoneSink: identifyMic ? microphoneSink : nil,
                                          microphoneGeneration: microphoneSink.currentGeneration())
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
                    return SpeechAnalyzerTranscriber(locale: locale) as any Transcribing
                }
            },
            makeProvider: { model in
                OllamaProvider(model: model, baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey(),
                               localOnly: ProviderSettings.aiMode != .cloud)
            },
            models: [
                .listener: ProviderSettings.model(for: .listener),
                .quick: ProviderSettings.model(for: .quick),
                .deep: ProviderSettings.model(for: .deep)
            ]
        ))
    }

    // MARK: - Ollama cloud routing

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
                Text("⚠️ \(startError)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .background(Theme.windowBackground)
            }
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
            if wantsCapture && session.isRunning && date >= nextSpeakerAnalysis {
                identifySpeakers(showSheet: false)
            }
        }
        .onChange(of: store.revision) { _, _ in _ = checkpoint() }
        .sheet(isPresented: $showSettings, onDismiss: {
            session.aiEnabled = ProviderSettings.aiMode != .off
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            appearance = ProviderSettings.appearance   // apply an appearance change live
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
            SessionSearchView(store: sessionStore, onClear: { dropCurrentSessionFromSaving() })
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
            session.aiEnabled = ProviderSettings.aiMode != .off
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            let preset = PresetCatalog.preset(id: presetID)
            session.personaGuidance = preset.personaGuidance
            ApplicationLifecycle.shared.prepareToClose = { await prepareToClose() }
            if !referencePaths.isEmpty { loadReferences(into: session) }
            hotkey.start { Task { await session.respondQuick(.answerQuestion) } }
            permissions.refresh()
            // First launch: walk the user through the guided onboarding (which includes the
            // permission grants). On later launches, only nudge the bare permissions panel when
            // a required grant is still missing; the shield button keeps it reachable otherwise.
            if !UserDefaults.standard.bool(forKey: OnboardingView.completionKey) {
                showOnboarding = true
            } else if !permissions.allRequiredGranted {
                showPermissions = true
            }
        }
        .task {
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
                Button("Full transcript (Markdown)…") { exportSession() }
                Button("Recap (Markdown)…") { exportRecap() }
                Button("PDF…") { exportPDF() }
                Button("Copy conversation") { copySessionMarkdown() }
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

    /// Listen/Stop press: start or stop capture, tracking the elapsed-timer anchor and saving on Stop.
    private func toggleCapture(session: MeetingSession) {
        guard !lifecycleBusy else { return }
        Task {
            if wantsCapture {
                lifecycleBusy = true
                defer { lifecycleBusy = false }
                _ = checkpoint()
                wantsCapture = false
                recordingStartedAt = nil
                restartTask?.cancel()   // cancel any in-flight locale restart
                // Await teardown so the transcriber flushes its final segments into the store
                // before we snapshot the transcript for search.
                await session.stopAndWait()
                _ = checkpoint(complete: true, force: true)
                Task { await finishSpeakerAnalysis() }
            } else {
                wantsCapture = true
                do {
                    startError = nil
                    // The Others buffer is reset in makeCapture, restarting its 0-based timeline.
                    // Clear stale labels + bump the token BEFORE start; anchor the run only AFTER
                    // start returns, once the prior Stop's finals have drained into the store.
                    beginDiarizationRunReset()
                    try await session.start()
                    guard wantsCapture, session.isRunning else { return }
                    anchorDiarizationRun()
                    now = Date(); recordingStartedAt = Date()
                } catch {
                    startError = error.localizedDescription
                    wantsCapture = false
                }
            }
        }
    }

    /// Restarts an active session after a language change so the new transcriber applies immediately
    /// (the locale is read only when a transcriber is created, at start). Called from the rail's
    /// Language picker binding.
    func restartForLocaleChange(session: MeetingSession) {
        restartTask?.cancel()
        restartTask = Task {
            await session.stopAndWait()   // await teardown so the new transcriber can't overlap the old
            // Bail if the user pressed Stop or closed the window during teardown — don't resume
            // recording against their intent.
            guard wantsCapture, !Task.isCancelled else { return }
            // The restart rebuilds the capture, resetting the Others buffer's 0-based timeline. Drop
            // stale labels + bump the token before start; anchor only after start returns (the prior
            // teardown above already drained, but the new finals land after start re-attaches).
            beginDiarizationRunReset()
            do {
                startError = nil
                try await session.start()
                guard wantsCapture, session.isRunning, !Task.isCancelled else { return }
                anchorDiarizationRun()
            } catch {
                startError = error.localizedDescription; wantsCapture = false
            }
        }
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
        speakerTask?.cancel()
        speakerTask = nil
        let run = diarizationRunToken + 1
        let remotePrefix = run == 1 ? "Speaker" : "Run \(run) speaker"
        let micPrefix = run == 1 ? "Mic speaker" : "Run \(run) mic speaker"
        speakerTrackers = [.others: SpeakerIdentityTracker(prefix: remotePrefix),
                           .you: SpeakerIdentityTracker(prefix: micPrefix)]
        speakerParticipants = []
        nextSpeakerAnalysis = .distantFuture
        speakerLoading = false
        speakerError = nil
        diarizationRunToken &+= 1
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
    private func anchorDiarizationRun() {
        diarizationRunStartIndex = store.utterances.count
        // Snapshot the settings the new run's capture/transcriber were built from. `makeCapture` read
        // `speakerDiarizationEnabled` to decide sink attachment and `makeTranscriber` read the engine,
        // both during the `start()` that just returned — so reading them now matches this run, and
        // re-enables Identify only when the sink is actually attached and live.
        diarizationSinkAttached = ProviderSettings.speakerDiarizationEnabled
        diarizationRunUsesTimestamps = ProviderSettings.transcriptionEngine == "whisperKit"
        microphoneSinkAttached = diarizationSinkAttached && ProviderSettings.microphoneDiarizationEnabled
        nextSpeakerAnalysis = Date().addingTimeInterval(20)
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
            let documents = await Task.detached { FileContextLoader.load(urls) }.value
            guard token == referenceLoadToken else { return }   // superseded by a newer add/clear
            session.referenceContext = ReferenceBuilder.build(
                documents: documents,
                maxChars: ProviderSettings.referenceBudget
            )
        }
    }

}

// MARK: - Actions (import / export / model refresh)

extension MeetingView {
    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

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
            if let info = await CalendarService.currentOrNextMeeting() {
                session.notes = MeetingContext.notes(
                    for: info,
                    timeFormat: { $0.formatted(date: .omitted, time: .shortened) })
            } else {
                startError = "No current/upcoming calendar meeting found (or calendar access denied)."
            }
        }
    }

    /// Builds the full Markdown document (transcript + AI-pane outputs) for the given timestamp.
    /// Shared by `exportSession()`, `exportPDF()`, and `copySessionMarkdown()`.
    func sessionMarkdown(now: Date = Date()) -> String {
        SessionExporter.markdown(
            title: conversationTitle,
            transcript: store.utterances,
            notes: session.notes,
            listenerSummary: session.listenerSummary,
            quickSuggestion: session.quickSuggestion,
            deepAnswer: session.deepAnswer
        )
    }

    /// Exports the current transcript + AI-pane outputs to a Markdown file via a save panel.
    func exportSession() {
        let now = Date()
        let markdown = sessionMarkdown(now: now)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "ListenToMe-\(Self.fileStampFormatter.string(from: now)).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try markdown.write(to: url, atomically: true, encoding: .utf8) } catch {
            startError = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Exports a concise recap (summary + Quick/Deep notes, no transcript) to a Markdown file.
    func exportRecap() {
        let now = Date()
        let markdown = SessionExporter.recap(
            title: conversationTitle,
            listenerSummary: session.listenerSummary,
            quickSuggestion: session.quickSuggestion,
            deepAnswer: session.deepAnswer
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "ListenToMe-recap-\(Self.fileStampFormatter.string(from: now)).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try markdown.write(to: url, atomically: true, encoding: .utf8) } catch {
            startError = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Renders the full Markdown document to a PDF and saves it via a save panel.
    func exportPDF() {
        let now = Date()
        let title = "ListenToMe Session — \(now.formatted(date: .abbreviated, time: .shortened))"
        let markdown = sessionMarkdown(now: now)
        guard let data = PDFExport.data(fromMarkdown: markdown, title: title) else {
            startError = "Couldn't render the PDF."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "ListenToMe-\(Self.fileStampFormatter.string(from: now)).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url) } catch {
            startError = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Copies the current transcript + AI-pane outputs to the clipboard as Markdown,
    /// mirroring `exportSession()`'s document but without a file save.
    func copySessionMarkdown() {
        Clipboard.copy(sessionMarkdown())
    }

    /// Window close/teardown: stop the hotkey and any pending restart/import. If recording, mirror
    /// the Stop-button flow so a meeting ended by closing the window is still saved for search
    /// (best-effort: the Task may not finish on a full app quit).
    func tearDownOnDisappear(session: MeetingSession) {
        hotkey.stop()
        for role in CopilotRole.allCases { session.cancelResponse(role) }
        speakerTask?.cancel()
        diarizationRunToken &+= 1
        let wasCapturing = wantsCapture
        wantsCapture = false
        restartTask?.cancel()   // don't let a pending locale restart resume capture after close
        importTask?.cancel()    // stop an in-flight file import when the window closes
        if wasCapturing {
            _ = checkpoint()
            Task {
                await session.stopAndWait()
                _ = checkpoint(complete: true, force: true)
            }
        } else {
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
        lastSavedSignature = ""
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
        chatModels = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey(), localOnly: ProviderSettings.aiMode != .cloud)
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
        let discovered = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey(), localOnly: ProviderSettings.aiMode != .cloud)
        guard token == modelLoadToken else { return }
        chatModels = discovered
        modelStatus = ProviderSettings.aiMode == .off ? "AI is off" : (chatModels.isEmpty
            ? "No available AI models. Check Ollama and AI mode in Settings, then Refresh models." : "")
        let defaults = ModelRanking.roleDefaults(from: chatModels)
        for role in CopilotRole.allCases {
            let current = session.models[role] ?? ""
            // Keep the user's explicit pick if it's still valid; otherwise follow the
            // role-appropriate default so the three panes don't all collapse to one model.
            let keepPinned = ProviderSettings.isPinned(role) && chatModels.contains(current)
            let target = keepPinned ? current : (defaults[role] ?? current)
            if target != current { ProviderSettings.setModel(target, for: role) }
            session.setModel(role, target)   // rebuild the provider so it picks up the new base URL/key
        }
    }
}
