import SwiftUI
import ListenToMeCore

struct MobileMeetingView: View {
    @Bindable var session: MobileSession
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showNotes = false
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
                GeometryReader { geometry in
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollView {
                            VStack(spacing: 10) {
                                transcriptPanel.frame(height: 300)
                                aiPanel(.quick).frame(height: 360)
                                aiPanel(.deep).frame(height: 360)
                            }
                        }.accessibilityIdentifier("dashboardScroll")
                    } else if verticalSizeClass == .compact {
                        HStack(spacing: 10) {
                            transcriptPanel
                            aiPanel(.quick)
                            aiPanel(.deep)
                        }
                    } else if geometry.size.width >= 700 {
                        HStack(spacing: 10) {
                            VStack(spacing: 10) {
                                transcriptPanel.frame(maxHeight: .infinity)
                                aiPanel(.quick).frame(maxHeight: .infinity)
                            }
                            aiPanel(.deep).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 10) {
                            transcriptPanel.frame(height: max(110, geometry.size.height * 0.42))
                            HStack(spacing: 8) {
                                aiPanel(.quick)
                                aiPanel(.deep)
                            }.frame(maxHeight: .infinity)
                        }
                    }
                }.padding(10)

            }
            .navigationTitle("ListenToMe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("History", systemImage: "clock") { showHistory = true }.disabled(session.busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button("Notes", systemImage: "note.text") { showNotes = true }
                        Menu("More", systemImage: "ellipsis.circle") {
                            Button("Full summary") { showFullSummary = true }
                            Button("Settings", systemImage: "gearshape") { showSettings = true }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .sheet(isPresented: $showHistory) { history }
            .sheet(isPresented: $showSettings) { settings }
            .sheet(isPresented: $showNotes) { MobileNotesView(session: session) }
            .sheet(isPresented: $showFullSummary) {
                NavigationStack { summary.navigationTitle("Full summary").toolbar { Button("Done") { showFullSummary = false } } }
            }
            .task(id: session.autoQuick && session.state == .recording) {
                guard session.autoQuick, session.state == .recording else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await session.updateQuickAutomatically()
                }
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 2 : 10) {
            TextField("Conversation title", text: $session.title)
                .focused($focusedField, equals: .title)
                .font(verticalSizeClass == .compact ? .headline : .title2.bold())
                .accessibilityIdentifier("conversationTitle")
                .disabled(session.isSummarizing)
                .onChange(of: session.title) { _, _ in session.save(announce: false) }
            Label(statusText, systemImage: session.state == .recording ? "waveform" : "mic")
                .font(.subheadline).foregroundStyle(session.state == .recording ? .red : .secondary)
            if verticalSizeClass != .compact {
                Text("Microphone only · On-device transcription")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = session.message {
                Text(message).font(.caption).lineLimit(3)
                    .accessibilityIdentifier("sessionMessage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(verticalSizeClass == .compact ? 6 : 16).background(.indigo.opacity(0.07))
    }

    private var statusText: String {
        switch session.state {
        case .idle: return "Ready to listen"
        case .preparing: return "Preparing speech model… First use may download a model."
        case .recording: return "Listening"
        case .stopping: return "Finishing transcript…"
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Live transcript", systemImage: "waveform").font(.headline).padding([.top, .horizontal], 10)
            transcript.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            .accessibilityIdentifier("transcriptPanel")
    }

    private func aiPanel(_ mode: MobileSummaryMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .quick ? "Quick Summary" : "Deep Summary").font(.headline)
            if mode == .quick {
                Toggle("Auto", isOn: $session.autoQuick).font(.caption)
                    .accessibilityLabel("Auto Quick Summary")
            }
            HStack {
                Button(session.generatingMode == mode ? "Updating…" : "Update") {
                    session.requestSummary(for: mode)
                }.buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityLabel("Generate \(mode.title)")
                    .disabled(session.summaryBlockReason(for: mode) != nil)
                if session.generatingMode == mode {
                    Button("Cancel") { session.cancelSummary() }.font(.caption)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if mode == .quick && session.autoQuick {
                        Text("Updates every 30 seconds while listening when text changes (at least 80 characters). Uses your selected provider.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let reason = session.summaryBlockReason(for: mode), !session.isSummarizing {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("reason-\(mode.rawValue)")
                    }
                    if session.generatingMode == mode {
                        Text(session.summaryDraft).font(.subheadline).textSelection(.enabled)
                    }
                    let output = session.output(for: mode)
                    Text(output.isEmpty ? "Your \(mode == .quick ? "quick summary" : "deep analysis") appears here." : output)
                        .font(.subheadline).textSelection(.enabled)
                        .accessibilityIdentifier("output-\(mode.rawValue)")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(mode == .quick ? Color.indigo.opacity(0.06) : Color.purple.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14))
    }

    private var transcript: some View {
        Group {
            if session.allSegments.isEmpty {
                ScrollView {
                    Text("Tap Start listening for live microphone transcription. Keep the app open while recording.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(session.allSegments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.isFinal ? "MICROPHONE" : "MICROPHONE · UNFINALIZED")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.indigo)
                                Text(segment.text).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding()
                }
            }
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("AI output", selection: $summaryMode) {
                    ForEach(MobileSummaryMode.allCases) { mode in Text(mode.title).tag(mode) }
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
                    Text(session.summaryDraft).textSelection(.enabled)
                }
                if !session.output(for: summaryMode).isEmpty {
                    Text(session.output(for: summaryMode)).textSelection(.enabled).accessibilityIdentifier("savedSummary")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
    }

    private var controls: some View {
        let layout = verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 12))
        return layout {
            Button {
                focusedField = nil
                if session.state == .idle { session.start() } else { Task { await session.stop() } }
            } label: {
                Label(session.state == .idle ? "Start listening" : "Stop listening",
                      systemImage: session.state == .idle ? "mic.fill" : "stop.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.state == .idle ? .indigo : .red)
            .disabled(session.state == .stopping || (session.isSummarizing && session.state == .idle))
            HStack {
                Button("Save", systemImage: "square.and.arrow.down") { session.save() }.disabled(!session.hasContent)
                Spacer()
                Button("New", systemImage: "plus") { session.newConversation() }.disabled(session.busy)
                Spacer()
                ShareLink(item: session.markdown) { Label("Share", systemImage: "square.and.arrow.up") }
                    .disabled(!session.hasContent)
            }.font(.subheadline.weight(.semibold))
        }.padding(verticalSizeClass == .compact ? 8 : 16).background(.bar)
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
                            Text(record.summary.isEmpty ? (record.notes ?? record.transcript) : record.summary)
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
                MobileAISettingsView(ai: session.ai).disabled(session.busy)
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
            .navigationTitle("Settings")
            .toolbar { Button("Done") { showSettings = false } }
        }
    }
}
