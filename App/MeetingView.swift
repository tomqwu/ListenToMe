import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

struct MeetingView: View {
    /// Anchor id for keeping scroll views pinned to their newest content.
    static let scrollBottomID = "scroll-bottom"

    @State private var session: MeetingSession
    @State private var store: ConversationStore
    @State private var startError: String?
    @State private var showSettings = false
    @State private var permissions = PermissionsModel()
    @State private var showPermissions = false
    @State private var showOnboarding = false
    @State private var chatModels: [String] = []
    @State private var transcriptionLocaleID: String
    @State private var presetID: String
    @State private var referencePaths: [URL]
    @State private var referenceLoadToken = 0
    @State private var restartTask: Task<Void, Never>?
    @State private var importTask: Task<Void, Never>?
    @State private var transcriptAtBottom = true
    /// User intent to be capturing — the toolbar button's source of truth. Stays true across the
    /// brief teardown window of a locale restart (when `session.isRunning` is transiently false),
    /// so a Stop press is never lost.
    @State private var wantsCapture = false
    private let hotkey = HotkeyMonitor()

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
        _session = State(initialValue: MeetingSession(
            store: store,
            context: ContextEngine(debounce: 8),
            makeCapture: { DualChannelCapture() },
            makeTranscriber: {
                let locale = ProviderSettings.transcriptionLocale()
                switch ProviderSettings.transcriptionEngine {
                case "speechRecognizer":
                    return SpeechRecognizerTranscriber(locale: locale) as any Transcribing
                case "whisperKit":
                    return WhisperKitTranscriber(locale: locale) as any Transcribing
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
            meetingToolbar(
                session: session,
                proactiveEnabled: $session.proactiveEnabled,
                showSettings: $showSettings,
                showPermissions: $showPermissions
            )
            if let startError {
                Text("⚠️ \(startError)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
            Divider()
            HSplitView {
                transcriptPane(session: session, notes: $session.notes)
                VSplitView {
                    listenerPane(session: session)
                    quickPane(session: session)
                    deepPane(session: session)
                }
                .frame(minWidth: 360)
            }
        }
        .frame(minWidth: 1100, minHeight: 560)
        .sheet(isPresented: $showSettings, onDismiss: {
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            // Rebuild attached references so a changed reference-budget takes effect immediately.
            if !referencePaths.isEmpty { loadReferences(into: session) }
            Task { await reloadAndHealModels() }
        }, content: {
            SettingsView()
        })
        .sheet(isPresented: $showPermissions) {
            PermissionsView(permissions: permissions)
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
        .onDisappear {
            hotkey.stop()
            wantsCapture = false
            restartTask?.cancel()   // don't let a pending locale restart resume capture after close
            importTask?.cancel()    // stop an in-flight file import when the window closes
            session.stop()
        }
    }

    // MARK: - Toolbar

    private func meetingToolbar(
        session: MeetingSession,
        proactiveEnabled: Binding<Bool>,
        showSettings: Binding<Bool>,
        showPermissions: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Button(wantsCapture ? "Stop" : "Listen") {
                Task {
                    if wantsCapture {
                        wantsCapture = false
                        restartTask?.cancel()   // cancel any in-flight locale restart
                        session.stop()
                    } else {
                        wantsCapture = true
                        do {
                            startError = nil
                            try await session.start()
                        } catch {
                            startError = error.localizedDescription
                            wantsCapture = false
                        }
                    }
                }
            }
            .disabled(session.isTranscribingFile)   // no live capture while importing a file
            if session.isRunning {
                RecordingIndicator()
                Text("Recording").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Language", selection: $transcriptionLocaleID) {
                ForEach(Self.languageOptions, id: \.id) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .onChange(of: transcriptionLocaleID) { _, newValue in
                ProviderSettings.transcriptionLocaleID = newValue
                // The locale is read only when a transcriber is created (at start). Restart an
                // active session so the new language applies immediately instead of next Listen.
                guard wantsCapture else { return }
                restartTask?.cancel()
                restartTask = Task {
                    await session.stopAndWait()   // await teardown so the new transcriber can't overlap the old
                    // Bail if the user pressed Stop or closed the window during teardown — don't
                    // resume recording against their intent.
                    guard wantsCapture, !Task.isCancelled else { return }
                    do { startError = nil; try await session.start() } catch {
                        startError = error.localizedDescription; wantsCapture = false
                    }
                }
            }
            .help("Transcription language — applies the next time you press Listen")
            Toggle("Proactive", isOn: proactiveEnabled)
            Button { Task { await reloadModels() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh installed Ollama models")
            Button { importAudioFile(session: session) } label: { Image(systemName: "waveform") }
                .help("Import an audio file and transcribe it")
                .disabled(wantsCapture || session.isTranscribingFile)   // wantsCapture covers the restart window
            if session.isTranscribingFile {
                ProgressView().controlSize(.small)
                Text("Transcribing…").foregroundStyle(.secondary)
            }
            Button { exportSession() } label: { Image(systemName: "square.and.arrow.up") }
                .help("Export the transcript and AI notes to a Markdown file")
            Button { showPermissions.wrappedValue = true } label: { Image(systemName: "lock.shield") }
            Button { showSettings.wrappedValue = true } label: { Image(systemName: "gearshape") }
        }
        .padding(10)
    }

    // MARK: - Transcript pane

    private func transcriptPane(session: MeetingSession, notes: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.paneSpacing) {
            HStack {
                Text("Transcript").font(.headline)
                Spacer()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if store.utterances.isEmpty && store.partial == nil {
                            PaneEmptyState(
                                systemImage: "waveform",
                                text: "Press Listen to start transcribing the conversation."
                            )
                        }
                        ForEach(store.utterances) { seg in
                            transcriptLine(for: seg)
                        }
                        if let partial = store.partial {
                            transcriptLine(for: partial).opacity(0.5)
                        }
                        Color.clear.frame(height: 1).id(Self.scrollBottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Follow the newest line only while the user is at the bottom; if they scroll up
                // to read history, stop auto-scrolling until they return to the bottom.
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 24
                } action: { _, atBottom in transcriptAtBottom = atBottom }
                .onChange(of: store.utterances.count) { _, _ in
                    if transcriptAtBottom { proxy.scrollTo(Self.scrollBottomID, anchor: .bottom) }
                }
                .onChange(of: store.partial?.text) { _, _ in
                    if transcriptAtBottom { proxy.scrollTo(Self.scrollBottomID, anchor: .bottom) }
                }
            }
            Picker("Preset", selection: $presetID) {
                ForEach(PresetCatalog.all) { preset in Text(preset.name).tag(preset.id) }
            }
            .labelsHidden()
            .onChange(of: presetID) { oldID, newID in
                let preset = PresetCatalog.preset(id: newID)
                let previousTemplate = PresetCatalog.preset(id: oldID).notesTemplate
                ProviderSettings.presetID = newID
                session.personaGuidance = preset.personaGuidance
                // Swap the notes scaffold only when the user hasn't edited it (notes still match the
                // previous preset's template, or are empty). This clears an unedited scaffold on
                // None, but preserves notes the user actually typed.
                if session.notes.isEmpty || session.notes == previousTemplate {
                    session.notes = preset.notesTemplate
                }
            }
            .help("Use-case preset — fills Context notes and tailors the AI panes")
            TextField("Context notes (injected into prompts)", text: notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            referenceFilesRow(session: session)
        }
        .paneCard()
        .padding(Theme.paneSpacing)
        .frame(minWidth: 360)
    }

    /// Attach/clear files & folders whose text is fed into Quick/Deep prompts as grounding.
    private func referenceFilesRow(session: MeetingSession) -> some View {
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

    private var referenceSummary: String {
        let names = referencePaths.map { $0.lastPathComponent }
        let shown = names.prefix(2).joined(separator: ", ")
        return referencePaths.count > 2 ? "\(shown) +\(referencePaths.count - 2) more" : shown
    }

    private func addReferenceFiles(session: MeetingSession) {
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

    private func clearReferences(session: MeetingSession) {
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

    private func transcriptLine(for seg: TranscriptSegment) -> some View {
        (Text(seg.source == .you ? "You: " : "Others: ")
            .foregroundStyle(seg.source == .you ? .blue : .green).bold()
         + Text(seg.text))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}

// MARK: - AI panes

extension MeetingView {
    func listenerPane(session: MeetingSession) -> some View {
        AIPaneView(
            title: "Listener",
            role: .listener,
            session: session,
            chatModels: chatModels,
            outputText: session.listenerSummary,
            placeholder: "Live summary & open items will appear here.",
            headerExtra: {
                AnyView(Button("Refresh") { Task { await session.refreshListener() } })
            },
            actionButtons: { AnyView(EmptyView()) }
        )
    }

    func quickPane(session: MeetingSession) -> some View {
        AIPaneView(
            title: "Quick",
            role: .quick,
            session: session,
            chatModels: chatModels,
            outputText: session.quickSuggestion,
            placeholder: "Press ⌘⇧Space or a button for a quick suggestion.",
            headerExtra: { AnyView(EmptyView()) },
            actionButtons: {
                AnyView(HStack {
                    Button("What should I answer?") { Task { await session.respondQuick(.answerQuestion) } }
                    Button("Recap so far") { Task { await session.respondQuick(.recap) } }
                    Button("Suggest a follow-up") { Task { await session.respondQuick(.followUp) } }
                })
            }
        )
    }

    func deepPane(session: MeetingSession) -> some View {
        AIPaneView(
            title: "Deep",
            role: .deep,
            session: session,
            chatModels: chatModels,
            outputText: session.deepAnswer,
            placeholder: "Ask for a detailed/coding answer.",
            headerExtra: { AnyView(EmptyView()) },
            actionButtons: {
                AnyView(Button("Deep answer") { Task { await session.respondDeep(.answerQuestion) } })
            }
        )
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

    /// Exports the current transcript + AI-pane outputs to a Markdown file via a save panel.
    func exportSession() {
        let now = Date()
        let markdown = SessionExporter.markdown(
            title: "ListenToMe Session — \(now.formatted(date: .abbreviated, time: .shortened))",
            transcript: store.utterances,
            notes: session.notes,
            listenerSummary: session.listenerSummary,
            quickSuggestion: session.quickSuggestion,
            deepAnswer: session.deepAnswer
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "ListenToMe-\(Self.fileStampFormatter.string(from: now)).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try markdown.write(to: url, atomically: true, encoding: .utf8) } catch {
            startError = "Export failed: \(error.localizedDescription)"
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
