import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

struct MeetingView: View {
    /// Anchor id for keeping scroll views pinned to their newest content.
    static let scrollBottomID = "scroll-bottom"

    @State private var session: MeetingSession
    @State var store: ConversationStore
    @State private var startError: String?
    @State private var showSettings = false
    @State private var permissions = PermissionsModel()
    @State private var showPermissions = false
    @State private var showOnboarding = false
    @State private var showSearch = false
    @State private var sessionStore = SessionStore()
    /// Identity of this app-window's session. Reused across Listen→Stop cycles so repeated Stops
    /// upsert one growing record instead of writing a fresh superset each time.
    @State private var currentSessionID = UUID().uuidString
    /// `lastSavedUtteranceCount`: count at the last save, so an unchanged transcript isn't re-saved on
    /// Stop. `sessionSaveable`: whether this window-session may be persisted — tainted to false the
    /// moment saving is ever observed off (or history is cleared), so "turn off to keep nothing" holds
    /// for the whole session. `savingEnabledBeforeSettings`: toggle value snapshotted when Settings
    /// opened, so an off→on round-trip is still caught.
    @State private var lastSavedUtteranceCount = 0; @State private var sessionSaveable = true
    @State private var savingEnabledBeforeSettings = true; @State var chatModels: [String] = []
    @State var transcriptionLocaleID: String
    @State var presetID: String
    @State private var referencePaths: [URL]
    @State private var referenceLoadToken = 0
    @State private var restartTask: Task<Void, Never>?
    @State private var importTask: Task<Void, Never>?
    @State var transcriptAtBottom = true
    /// User intent to be capturing — the toolbar button's source of truth. Stays true across the
    /// brief teardown window of a locale restart (when `session.isRunning` is transiently false),
    /// so a Stop press is never lost.
    @State var wantsCapture = false
    /// When the current recording run began, for the elapsed mm:ss timer. nil while idle.
    @State private var recordingStartedAt: Date?
    /// Ticks while recording so the elapsed timer updates once per second.
    @State private var now = Date()
    /// Live appearance (System/Light/Dark) applied to the root via `.preferredColorScheme`.
    @State private var appearance = ProviderSettings.appearance
    /// Accumulates the `.others` channel (16 kHz mono) across a session for on-demand speaker
    /// diarization. Reset at each session start; read via `snapshot()` when identifying speakers.
    @State private var othersAudioSink: SpeakerAudioBuffer
    /// Drives the experimental "Speaker breakdown" sheet and holds its result/error/in-flight state.
    @State var showSpeakerBreakdown = false
    @State var speakerSummary: SpeakerSummary?
    @State var speakerError: String?
    @State var speakerLoading = false
    /// Per-line speaker labels (transcript-line id → "Speaker N") for the OTHERS channel, filled by
    /// "Identify speakers" when the WhisperKit engine supplies real per-line timestamps. Reset at
    /// each session start so stale labels from a previous meeting don't linger.
    @State var speakerLabels: [UUID: String] = [:]
    private let diarizer = SpeakerDiarizer()
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
        _session = State(initialValue: MeetingSession(
            store: store,
            context: ContextEngine(debounce: 8),
            makeCapture: {
                // Only accumulate the Others channel for diarization when the experimental setting
                // is on — otherwise a normal meeting needlessly resamples + retains up to ~2 h of
                // audio. Read at capture-creation time so toggling it before the next Listen applies.
                let diarize = ProviderSettings.speakerDiarizationEnabled
                if diarize { othersSink.reset() }
                return DualChannelCapture(othersSink: diarize ? othersSink : nil)
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
                OllamaProvider(model: model, baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
            },
            models: [
                .listener: ProviderSettings.model(for: .listener),
                .quick: ProviderSettings.model(for: .quick),
                .deep: ProviderSettings.model(for: .deep)
            ]
        ))
    }

    // MARK: - Ollama cloud routing

    private static func ollamaKey() -> String? {
        let k = KeychainStore.get("ollama")
        return (k?.isEmpty == false) ? k : nil
    }

    private static func ollamaBaseURL() -> URL {
        ollamaKey() != nil
            ? URL(string: "https://ollama.com")!
            : URL(string: "http://localhost:11434")!
    }

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            topControlBar(session: session, showPermissions: $showPermissions)
            if let startError {
                Text("⚠️ \(startError)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .background(Theme.windowBackground)
            }
            HStack(spacing: 0) {
                statusRail(session: session)
                transcriptColumn(session: session, notes: $session.notes)
                    .layoutPriority(1)
                copilotColumn(session: session)
            }
            .frame(maxHeight: .infinity)
            CommandCenterFooter(cloudActive: Self.ollamaKey() != nil)
        }
        .background(Theme.windowBackground)
        .preferredColorScheme(colorScheme(for: appearance))
        .frame(minWidth: 1100, minHeight: 560)
        // Tick the elapsed timer once per second while recording.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            if recordingStartedAt != nil { now = date }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
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
        .sheet(isPresented: $showSearch) {
            SessionSearchView(store: sessionStore, onClear: { dropCurrentSessionFromSaving() })
        }
        .sheet(isPresented: $showSpeakerBreakdown) {
            SpeakerBreakdownView(
                loading: speakerLoading, summary: speakerSummary, errorText: speakerError,
                didTruncate: othersAudioSink.didTruncate,
                perLineLabelsUnavailable: ProviderSettings.transcriptionEngine != "whisperKit")
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            // Onboarding may have set/cleared the Ollama key, which changes the route; rebuild
            // every role's provider so the panes use the new local/cloud configuration.
            Task { await reloadAndHealModels() }
        }, content: {
            OnboardingView()
        })
        .onAppear {
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            let preset = PresetCatalog.preset(id: presetID)
            session.personaGuidance = preset.personaGuidance
            if session.notes.isEmpty { session.notes = preset.notesTemplate }   // seed saved preset's scaffold
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
        .onDisappear { tearDownOnDisappear(session: session) }
    }

    // MARK: - Top control bar

    /// Replaces the old icon-row toolbar: Listen/Stop + pulsing indicator + elapsed timer on the
    /// left; the same icon actions that existed before on the right (refresh-models, import audio,
    /// export menu, copy-session, search, permissions, settings).
    private func topControlBar(session: MeetingSession, showPermissions: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Button(wantsCapture ? "Stop" : "Listen") { toggleCapture(session: session) }
                .buttonStyle(.borderedProminent)
                .disabled(session.isTranscribingFile)   // no live capture while importing a file
            if session.isRunning {
                RecordingIndicator()
                Text(elapsedLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink2)
            }
            if session.isTranscribingFile {
                ProgressView().controlSize(.small)
                Text("Transcribing…").foregroundStyle(Theme.ink2)
            }
            Spacer()
            Button { Task { await reloadModels() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh installed Ollama models")
            Button { importAudioFile(session: session) } label: { Image(systemName: "waveform") }
                .help("Import an audio file and transcribe it")
                .disabled(wantsCapture || session.isTranscribingFile)   // wantsCapture covers the restart window
            Menu {
                Button("Full transcript (Markdown)…") { exportSession() }
                Button("Recap (Markdown)…") { exportRecap() }
                Button("PDF…") { exportPDF() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuIndicator(.hidden)
            .help("Export the session as Markdown or PDF")
            Button { copySessionMarkdown() } label: { Image(systemName: "list.clipboard") }
                .help("Copy the transcript + AI notes as Markdown")
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                .help("Search past meetings")
            Button { showPermissions.wrappedValue = true } label: { Image(systemName: "lock.shield") }
                .help("Microphone / system-audio permissions")
            Button { openSettings($showSettings) } label: { Image(systemName: "gearshape") }
                .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.windowBackground)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    /// Listen/Stop press: start or stop capture, tracking the elapsed-timer anchor and saving on Stop.
    private func toggleCapture(session: MeetingSession) {
        Task {
            if wantsCapture {
                wantsCapture = false
                recordingStartedAt = nil
                restartTask?.cancel()   // cancel any in-flight locale restart
                // Await teardown so the transcriber flushes its final segments into the store
                // before we snapshot the transcript for search.
                await session.stopAndWait()
                saveSessionIfEnabled(session: session)
            } else {
                wantsCapture = true
                do {
                    startError = nil
                    // Clear any speaker labels from a previous meeting so they don't linger over the
                    // new session's transcript (the Others buffer is reset in makeCapture).
                    speakerLabels = [:]
                    try await session.start()
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
            do { startError = nil; try await session.start() } catch {
                startError = error.localizedDescription; wantsCapture = false
            }
        }
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
    private func sessionMarkdown(now: Date = Date()) -> String {
        SessionExporter.markdown(
            title: "ListenToMe Session — \(now.formatted(date: .abbreviated, time: .shortened))",
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
            title: "ListenToMe Session — \(now.formatted(date: .abbreviated, time: .shortened))",
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
        let wasCapturing = wantsCapture
        wantsCapture = false
        restartTask?.cancel()   // don't let a pending locale restart resume capture after close
        importTask?.cancel()    // stop an in-flight file import when the window closes
        if wasCapturing {
            Task { await session.stopAndWait(); saveSessionIfEnabled(session: session) }
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
        if !store.utterances.isEmpty { sessionSaveable = false }
        currentSessionID = UUID().uuidString
        lastSavedUtteranceCount = store.utterances.count
    }

    /// On Stop, persist the finished session for cross-meeting search when this window-session is
    /// saveable (saving never observed off), saving is on, and there's new transcript. Reuses
    /// `currentSessionID` so repeated Listen→Stop cycles upsert one growing record. Title = the
    /// active preset's name (or "Session") plus the date.
    func saveSessionIfEnabled(session: MeetingSession) {
        guard ProviderSettings.saveSessionsForSearch else { sessionSaveable = false; return }
        guard sessionSaveable, store.utterances.count > lastSavedUtteranceCount else { return }
        let now = Date()
        let presetName = PresetCatalog.preset(id: presetID).name
        let base = (presetName.isEmpty || presetName == "None") ? "Session" : presetName
        let transcript = store.utterances.map { "\($0.source == .you ? "You" : "Others"): \($0.text)" }
            .joined(separator: "\n")
        let record = SessionRecord(
            id: currentSessionID,
            title: "\(base) — \(now.formatted(date: .abbreviated, time: .shortened))",
            date: now,
            transcript: transcript,
            summary: session.listenerSummary
        )
        sessionStore.add(record)
        lastSavedUtteranceCount = store.utterances.count
    }

    /// Experimental: presents the Speaker breakdown sheet and runs FluidAudio diarization over the
    /// captured Others-channel snapshot off the main actor, publishing the summary or a friendly
    /// error. The sheet (`SpeakerBreakdownView`) renders the loading / error / needs-more-audio /
    /// results states from this same `@State`.
    func identifySpeakers() {
        speakerSummary = nil
        speakerError = nil
        speakerLoading = true
        showSpeakerBreakdown = true
        let samples = othersAudioSink.snapshot()
        let offset = othersAudioSink.startOffset
        // Inline per-line labels need real start/end timestamps; only WhisperKit populates those.
        let canLabelInline = ProviderSettings.transcriptionEngine == "whisperKit"
        let transcript = store.utterances
        Task {
            do {
                let outcome = try await diarizer.analyze(samples: samples)
                speakerSummary = outcome.summary
                if canLabelInline {
                    speakerLabels = SpeakerLabeling.label(
                        transcript: transcript, diarized: outcome.segments, offset: offset)
                } else {
                    speakerLabels = [:]
                }
            } catch {
                speakerError = error.localizedDescription
            }
            speakerLoading = false
        }
    }

    /// Reloads the installed Ollama chat models into the per-pane pickers.
    func reloadModels() async {
        chatModels = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
    }

    /// Reloads chat models for the current Ollama route (cloud vs local) and heals each role:
    /// keep the current model if it exists on the new route, otherwise fall back to a
    /// role-appropriate default (Quick = lightest, Deep = heaviest, Listener = balanced).
    /// Always rebuilds every role's provider so it picks up the current base URL/key.
    func reloadAndHealModels() async {
        chatModels = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
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
