import SwiftUI
import ListenToMeCore

struct MeetingView: View {
    @State private var session: MeetingSession
    @State private var store: ConversationStore
    @State private var startError: String?
    @State private var showSettings = false
    @State private var permissions = PermissionsModel()
    @State private var showPermissions = false
    private let hotkey = HotkeyMonitor()

    init() {
        let store = ConversationStore()
        let router = ModelRouter(default: OllamaProvider(model: ProviderSettings.ollamaModel))
        _store = State(initialValue: store)
        _session = State(initialValue: MeetingSession(
            store: store,
            router: router,
            context: ContextEngine(debounce: 8),
            makeCapture: { DualChannelCapture() },
            makeTranscriber: {
                ProviderSettings.transcriptionEngine == "speechRecognizer"
                    ? SpeechRecognizerTranscriber() as any Transcribing
                    : SpeechAnalyzerTranscriber() as any Transcribing
            }
        ))
    }

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            toolbar(
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
                suggestionPane(session)
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .sheet(isPresented: $showSettings) {
            SettingsView(router: session.router)
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsView(permissions: permissions)
        }
        .onAppear {
            hotkey.start { Task { await session.respond(.answerQuestion) } }
            permissions.refresh()
            if !permissions.allRequiredGranted { showPermissions = true }
        }
        .task {
            let chat = await OllamaModels.chatModels()
            guard !chat.isEmpty, !chat.contains(ProviderSettings.ollamaModel),
                  let model = OllamaModels.preferredChatModel(from: chat) else { return }
            ProviderSettings.ollamaModel = model
            let router = session.router
            router.register(OllamaProvider(model: model))
            router.setActive("ollama")
        }
        .onDisappear {
            hotkey.stop()
            session.stop()
        }
    }

    private func toolbar(
        session: MeetingSession,
        proactiveEnabled: Binding<Bool>,
        showSettings: Binding<Bool>,
        showPermissions: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Button(session.isRunning ? "Stop" : "Listen") {
                Task {
                    if session.isRunning {
                        session.stop()
                    } else {
                        do {
                            startError = nil
                            try await session.start()
                        } catch {
                            startError = error.localizedDescription
                        }
                    }
                }
            }
            if session.isRunning {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("Recording").foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Proactive", isOn: proactiveEnabled)
            Button("What should I answer?") { Task { await session.respond(.answerQuestion) } }
            Button("Recap so far") { Task { await session.respond(.recap) } }
            Button("Suggest a follow-up") { Task { await session.respond(.followUp) } }
            Button { showPermissions.wrappedValue = true } label: { Image(systemName: "lock.shield") }
            Button { showSettings.wrappedValue = true } label: { Image(systemName: "gearshape") }
        }
        .padding(10)
    }

    private func transcriptPane(session: MeetingSession, notes: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text("Transcript").font(.headline).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.utterances) { seg in
                        line(for: seg)
                    }
                    if let partial = store.partial {
                        line(for: partial).opacity(0.5)
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

    private func line(for seg: TranscriptSegment) -> some View {
        (Text(seg.source == .you ? "You: " : "Others: ")
            .foregroundStyle(seg.source == .you ? .blue : .green).bold()
         + Text(seg.text))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionPane(_ session: MeetingSession) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Suggestion").font(.headline)
                if session.isStreaming { ProgressView().controlSize(.small) }
            }
            ScrollView {
                Group {
                    if !session.suggestion.isEmpty {
                        Text(session.suggestion)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else if session.isStreaming {
                        Text("💭 Thinking…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Press ⌘⇧Space or a button to get a suggestion.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(minWidth: 360)
    }
}
