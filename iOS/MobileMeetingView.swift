import SwiftUI
import ListenToMeCore

struct MobileMeetingView: View {
    @Bindable var session: MobileSession
    @State private var showHistory = false
    @State private var workspace = MobileWorkspace.live
    @State private var modelRole: MobileSummaryMode?
    @State private var showSettings = false
    @State private var showNotes = false
    @State private var showCalendar = false
    @State private var showFullSummary = false
    @State private var summaryMode = MobileSummaryMode.summary
    @State private var pendingDeletion: SessionRecord?
    @State private var showDeletion = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var focusedField: EditingField?
    private enum EditingField { case title, notes }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                status
                MobileWorkspaceView(session: session, selection: $workspace) { role in
                    if session.ai.provider == .apple { showSettings = true } else { modelRole = role }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ListenToMe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button("History", systemImage: "clock") { showHistory = true }.disabled(session.busy)
                        Button("New", systemImage: "plus") { session.newConversation() }.disabled(session.busy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Menu("More", systemImage: "ellipsis.circle") {
                            ShareLink(item: session.markdown) { Label("Share", systemImage: "square.and.arrow.up") }
                                .disabled(!session.hasContent)
                            Button("Import from Calendar", systemImage: "calendar") { showCalendar = true }
                            Button("Full summary") { showFullSummary = true }
                            Button("Settings", systemImage: "gearshape") { showSettings = true }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .sheet(isPresented: $showHistory) { history }
            .sheet(isPresented: $showSettings) { settings }
            .sheet(item: $modelRole) { role in
                NavigationStack {
                    MobileRoleModelView(ai: session.ai, role: role)
                        .toolbar { Button("Done") { modelRole = nil } }
                }
            }
            .sheet(isPresented: $showCalendar) { MobileCalendarView(session: session) }
            .sheet(isPresented: $showNotes) { MobileNotesView(session: session) }
            .sheet(isPresented: $showFullSummary) {
                NavigationStack { summary.navigationTitle("Full summary").toolbar { Button("Done") { showFullSummary = false } } }
            }

        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Conversation title", text: $session.title)
                .focused($focusedField, equals: .title)
                .font(verticalSizeClass == .compact ? .headline : .title2.weight(.semibold))
                .accessibilityIdentifier("conversationTitle")
                .disabled(session.isSummarizing)
                .onChange(of: session.title) { _, _ in session.save(announce: false) }
            Label(statusText, systemImage: session.state == .recording ? "record.circle" : "mic")
                .font(.caption).foregroundStyle(session.state == .recording ? .red : .secondary)
            if let message = session.message {
                Text(message).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sessionMessage")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, verticalSizeClass == .compact ? 6 : 14)
    }

    private var statusText: String {
        switch session.state {
        case .idle: return "Ready to listen"
        case .preparing: return "Preparing speech model… First use may download a model."
        case .recording: return "Listening"
        case .stopping: return "Finishing transcript…"
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("AI output", selection: $summaryMode) {
                    ForEach(MobileSummaryMode.allCases) { mode in
                        Text(mode.title).tag(mode).accessibilityIdentifier("summary-option-\(mode.rawValue)")
                    }
                }.accessibilityIdentifier("summaryMode").disabled(session.isSummarizing)
                Text(summaryMode.title).font(.title2.bold())
                Text(session.ai.provider == .ollama
                     ? "Ollama Cloud · \(session.ai.selectedModel(for: summaryMode)). Summarize sends your notes and transcript to Ollama. Review the result."
                     : "Apple Intelligence summarizes your notes and transcript on this device. Review the result for accuracy.")
                    .foregroundStyle(.secondary)
                if let reason = session.summaryBlockReason(for: summaryMode) {
                    Text(reason).font(.callout).accessibilityIdentifier("summaryBlockReason")
                    if !session.isSummarizing {
                        Button("Check again") { session.recheckSummary(for: summaryMode) }
                    }
                }
                Button {
                    session.requestSummary(for: summaryMode)
                } label: {
                    Label(session.isSummarizing ? "Summarizing…" : "Generate \(summaryMode.title)", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.summaryBlockReason(for: summaryMode) != nil)
                if session.isSummarizing {
                    Button("Cancel summary") { session.cancelSummary() }
                    MarkdownText(text: session.summaryDraft).textSelection(.enabled)
                }
                if !session.output(for: summaryMode).isEmpty {
                    MarkdownText(text: session.output(for: summaryMode))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("savedSummary")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { session.save() } label: {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down").font(.body)
                    Text("Save").font(.caption2)
                }.frame(minWidth: 40, minHeight: 44)
            }.disabled(!session.hasContent).accessibilityLabel("Save")
            Button {
                focusedField = nil
                if session.state == .idle { session.start() } else { Task { await session.stop() } }
            } label: {
                Label(session.state == .idle ? "Start listening" : "Stop listening",
                      systemImage: session.state == .idle ? "mic.fill" : "stop.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent)
                .tint(session.state == .idle ? .indigo : .red)
                .disabled(session.state == .stopping || (session.isSummarizing && session.state == .idle))
            Button { showNotes = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "note.text").font(.body)
                    Text("Notes").font(.caption2)
                }.frame(minWidth: 40, minHeight: 44)
            }.accessibilityLabel("Notes")
        }.frame(maxWidth: 600).frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
    }

    private var history: some View {
        NavigationStack {
            List(session.history) { record in
                HStack {
                    Button {
                        session.open(record); showHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).font(.headline).foregroundStyle(.primary)
                            Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text(record.summary.isEmpty ? AttributedString(record.notes ?? record.transcript)
                                 : MarkdownText.inlineAttributed(record.summary))
                                .lineLimit(2).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = record; showDeletion = true }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(record.title)")
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDeletion = record; showDeletion = true }
                }
            }
            .alert("Delete conversation?", isPresented: $showDeletion, presenting: pendingDeletion) { record in
                Button("Delete conversation", role: .destructive) {
                    session.deleteConversation(id: record.id)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text("This removes the transcript, notes, attachments and all AI outputs from this device. It cannot be undone.")
            }
            .overlay { if session.history.isEmpty { ContentUnavailableView("No saved conversations", systemImage: "clock") } }
            .navigationTitle("History")
            .toolbar { Button("Done") { showHistory = false } }
        }
    }

    private var releaseVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    private var settings: some View {
        NavigationStack {
            Form {
                MobileAISettingsView(ai: session.ai)
                Section("Transcription") {
                    Picker("Language", selection: $session.language) {
                        Text("System (\(Locale.current.identifier))").tag(Locale.current.identifier)
                        ForEach(["en-US", "en-GB", "zh-CN", "zh-TW", "fr-FR", "de-DE", "ja-JP", "es-ES"]
                            .filter { $0 != Locale.current.identifier }, id: \.self) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale)
                        }
                    }.disabled(session.busy)
                    Text("Speech models may download on first use. Audio is transcribed on your device and is not saved.")
                }
                Section("Recording") {
                    Text("This version records the microphone while the app is open. " +
                         "Backgrounding, calls, or disconnecting the microphone stops recording and saves the conversation.")
                    Text("System audio, call recording, Mac sync and speaker identification are not included.")
                }
                Section("Privacy") {
                    Text("Conversations stay in this app's storage. Apple Intelligence summaries are optional and run on-device. " +
                         "Ollama Cloud sends notes and transcript when you generate a summary or enable Auto Quick Summary. " +
                         "API keys stay in this device's Keychain. Share exports text to the destination you choose.")
                    Link("Open app settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                Section("Release") {
                    LabeledContent("Version", value: releaseVersion)
                    Text("iPhone & iPad · iOS 26 or later")
                }
            }
            .accessibilityIdentifier("aiSettingsForm")
            .navigationTitle("Settings")
            .toolbar { Button("Done") { showSettings = false } }
        }
    }
}
