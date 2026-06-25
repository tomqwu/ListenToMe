import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

struct MeetingView: View {
    @State private var session: MeetingSession
    @State private var store: ConversationStore
    @State private var startError: String?
    @State private var showSettings = false
    @State private var permissions = PermissionsModel()
    @State private var showPermissions = false
    @State private var chatModels: [String] = []
    @State private var transcriptionLocaleID: String
    @State private var restartTask: Task<Void, Never>?
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
        let store = ConversationStore()
        _store = State(initialValue: store)
        _session = State(initialValue: MeetingSession(
            store: store,
            context: ContextEngine(debounce: 8),
            makeCapture: { DualChannelCapture() },
            makeTranscriber: {
                let locale = ProviderSettings.transcriptionLocale()
                return ProviderSettings.transcriptionEngine == "speechRecognizer"
                    ? (SpeechRecognizerTranscriber(locale: locale) as any Transcribing)
                    : (SpeechAnalyzerTranscriber(locale: locale) as any Transcribing)
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
            Task { await reloadAndHealModels() }
        }, content: {
            SettingsView()
        })
        .sheet(isPresented: $showPermissions) {
            PermissionsView(permissions: permissions)
        }
        .onAppear {
            session.responseLanguage = ProviderSettings.responseLanguageDirective()
            hotkey.start { Task { await session.respondQuick(.answerQuestion) } }
            permissions.refresh()
            if !permissions.allRequiredGranted { showPermissions = true }
        }
        .task {
            await reloadAndHealModels()
        }
        .onDisappear {
            hotkey.stop()
            wantsCapture = false
            restartTask?.cancel()   // don't let a pending locale restart resume capture after close
            session.stop()
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    /// Exports the current transcript + AI-pane outputs to a Markdown file via a save panel.
    private func exportSession() {
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
        do { try markdown.write(to: url, atomically: true, encoding: .utf8) }
        catch { startError = "Export failed: \(error.localizedDescription)" }
    }

    /// Reloads the installed Ollama chat models into the per-pane pickers.
    private func reloadModels() async {
        chatModels = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
    }

    /// Reloads chat models for the current Ollama route (cloud vs local) and heals each role:
    /// keep the current model if it exists on the new route, otherwise fall back to a
    /// role-appropriate default (Quick = lightest, Deep = heaviest, Listener = balanced).
    /// Always rebuilds every role's provider so it picks up the current base URL/key.
    private func reloadAndHealModels() async {
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
            session.setModel(role, target)   // always rebuild the provider so it picks up the new base URL/key
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
            if session.isRunning {
                Circle().fill(.red).frame(width: 10, height: 10)
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
                    do { startError = nil; try await session.start() }
                    catch { startError = error.localizedDescription; wantsCapture = false }
                }
            }
            .help("Transcription language — applies the next time you press Listen")
            Toggle("Proactive", isOn: proactiveEnabled)
            Button { Task { await reloadModels() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh installed Ollama models")
            Button { exportSession() } label: { Image(systemName: "square.and.arrow.up") }
                .help("Export the transcript and AI notes to a Markdown file")
            Button { showPermissions.wrappedValue = true } label: { Image(systemName: "lock.shield") }
            Button { showSettings.wrappedValue = true } label: { Image(systemName: "gearshape") }
        }
        .padding(10)
    }

    // MARK: - Transcript pane

    private func transcriptPane(session: MeetingSession, notes: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text("Transcript").font(.headline).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.utterances) { seg in
                        transcriptLine(for: seg)
                    }
                    if let partial = store.partial {
                        transcriptLine(for: partial).opacity(0.5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("Context notes (injected into prompts)", text: notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .frame(minWidth: 360)
    }

    private func transcriptLine(for seg: TranscriptSegment) -> some View {
        (Text(seg.source == .you ? "You: " : "Others: ")
            .foregroundStyle(seg.source == .you ? .blue : .green).bold()
         + Text(seg.text))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI panes

    private func listenerPane(session: MeetingSession) -> some View {
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

    private func quickPane(session: MeetingSession) -> some View {
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

    private func deepPane(session: MeetingSession) -> some View {
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

// MARK: - AIPaneView

private struct AIPaneView: View {
    let title: String
    let role: CopilotRole
    let session: MeetingSession
    let chatModels: [String]
    let outputText: String
    let placeholder: String
    let headerExtra: () -> AnyView
    let actionButtons: () -> AnyView

    private func modelOptions() -> [String] {
        let current = session.models[role] ?? ""
        if chatModels.contains(current) { return chatModels }
        return current.isEmpty ? chatModels : [current] + chatModels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                if session.streamingRoles.contains(role) {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                headerExtra()
                Picker("Model", selection: Binding(
                    get: { session.models[role] ?? "" },
                    set: {
                        session.setModel(role, $0)
                        ProviderSettings.setModel($0, for: role)
                        ProviderSettings.pin(role)   // explicit choice: stop auto-defaulting this pane
                    }
                )) {
                    ForEach(modelOptions(), id: \.self) { model in
                        Text("\(model) — \(ModelRanking.describe(model))").tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            ScrollView {
                Group {
                    if !outputText.isEmpty {
                        MarkdownText(text: outputText)
                            .foregroundStyle(.primary)
                    } else if session.streamingRoles.contains(role) {
                        Text("💭 Thinking…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            actionButtons()
        }
        .padding(10)
        .frame(minHeight: 160)
    }
}
