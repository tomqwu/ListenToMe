import SwiftUI
import ListenToMeCore

// MARK: - Command-center panes (need MeetingView's private state)
//
// The left status rail, the center timestamped transcript, and the right Copilot column. These live
// on `MeetingView` because they read/write its `@State`; the leaf views they compose are in
// `CommandCenter.swift`.

extension MeetingView {

    // MARK: Left status rail

    func statusRail(session: MeetingSession) -> some View {
        @Bindable var session = session
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RailRecStatus(isRunning: session.isRunning, elapsed: elapsedLabel)

                railSection("Engine") {
                    Text(CommandCenterLabels.engine(ProviderSettings.transcriptionEngine))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                    Picker("Language", selection: languageBinding(session: session)) {
                        ForEach(Self.languageOptions, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden().controlSize(.small)
                    .help("Transcription language — applies the next time you press Listen")
                }

                railSection("Proactive") {
                    Toggle("Proactive replies", isOn: $session.proactiveEnabled)
                        .controlSize(.small).labelsHidden()
                        .toggleStyle(.switch)
                        .help("Let Quick/Listener react automatically as the conversation flows")
                }

                railSection("Preset") {
                    Picker("Preset", selection: presetBinding(session: session)) {
                        ForEach(PresetCatalog.all) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().controlSize(.small)
                    .help("Use-case preset — fills Context notes and tailors the AI panes")
                }

                railSection("Models") {
                    ForEach(CopilotRole.allCases, id: \.self) { role in
                        modelPicker(role: role, session: session, label: railRoleName(role))
                    }
                }

                railSection("Session") {
                    StatRow(key: "turns", value: "\(store.utterances.count)")
                    StatRow(key: "you / others", value: "\(youCount) / \(othersCount)")
                    StatRow(key: "~tok", value: "\(approxTokens)")
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 210)
        .background(Theme.windowBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }

    private func railSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RailLabel(text: title)
            content()
        }
    }

    private func railRoleName(_ role: CopilotRole) -> String {
        switch role {
        case .listener: return "listener"
        case .quick: return "quick"
        case .deep: return "deep"
        }
    }

    // Real-only session stats.
    private var youCount: Int { store.utterances.filter { $0.source == .you }.count }
    private var othersCount: Int { store.utterances.filter { $0.source == .others }.count }
    /// Explicit ~chars/4 estimate (labeled "~tok"), never a fabricated exact count.
    private var approxTokens: Int { store.utterances.reduce(0) { $0 + $1.text.count } / 4 }

    // MARK: Center transcript

    /// "idle" when stopped; otherwise "live · N src" where N is the real number of distinct speaker
    /// sources actually captured so far (so it never claims system audio that isn't being captured).
    func transcriptStatusLabel(session: MeetingSession) -> String {
        guard session.isRunning else { return "idle" }
        let sources = Set(store.utterances.map(\.source)).count
        return sources > 0 ? "live · \(sources) src" : "live"
    }

    func transcriptColumn(session: MeetingSession, notes: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Transcript")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(transcriptStatusLabel(session: session))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chip))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)

            transcriptScroll(session: session)

            transcriptInputZone(session: session, notes: notes)
        }
        .background(Theme.cardBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }

    private func transcriptScroll(session: MeetingSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if store.utterances.isEmpty && store.partial == nil {
                        PaneEmptyState(
                            systemImage: "waveform",
                            text: "Press Listen to start transcribing the conversation.")
                    }
                    ForEach(store.utterances) { transcriptRow(for: $0) }
                    if let partial = store.partial {
                        transcriptRow(for: partial).opacity(0.5)
                    }
                    Color.clear.frame(height: 1).id(Self.scrollBottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            // Follow the newest line only while the user is at the bottom; if they scroll up to read
            // history, stop auto-scrolling until they return to the bottom.
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
        .frame(maxHeight: .infinity)
    }

    private func transcriptRow(for seg: TranscriptSegment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(CommandCenterLabels.stamp(seg.start))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.ink3)
                .frame(width: 40, alignment: .leading)
            Text(seg.source == .you ? "YOU" : "OTHERS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(seg.source == .you ? Theme.you : Theme.others)
                .frame(width: 52, alignment: .leading)
            Text(seg.text)
                .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private func transcriptInputZone(session: MeetingSession, notes: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { loadFromCalendar(session: session) } label: {
                Label("Load from Calendar", systemImage: "calendar")
            }
            .controlSize(.small)
            .help("Fill Context notes from your current or next calendar meeting")
            TextField("Context notes (injected into prompts)", text: notes, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
            referenceFilesRow(session: session)
        }
        .padding(12)
        .background(Theme.cardBackground2)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    // MARK: Right Copilot column

    func copilotColumn(session: MeetingSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Copilot")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("3 models")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chip))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)

            VSplitView {
                listenerBox(session: session)
                quickBox(session: session)
                deepBox(session: session)
            }
        }
        .frame(minWidth: 340)
        .background(Theme.cardBackground)
    }

    private func listenerBox(session: MeetingSession) -> some View {
        RoleBox(
            title: "Listener", accent: Theme.others, role: .listener, session: session,
            outputText: session.listenerSummary,
            placeholder: "Live summary & open items will appear here.",
            headerExtra: {
                Button("Refresh") { Task { await session.refreshListener() } }
                    .controlSize(.small)
            },
            actions: { EmptyView() })
    }

    private func quickBox(session: MeetingSession) -> some View {
        RoleBox(
            title: "Quick", accent: Theme.accent, role: .quick, session: session,
            outputText: session.quickSuggestion,
            placeholder: "Press ⌘⇧Space or a button for a quick suggestion.",
            headerExtra: { EmptyView() },
            actions: {
                HStack(spacing: 7) {
                    Button("What should I answer?") {
                        Task { await session.respondQuick(.answerQuestion) }
                    }
                    Button("Recap so far") { Task { await session.respondQuick(.recap) } }
                    Button("Suggest a follow-up") { Task { await session.respondQuick(.followUp) } }
                }
                .controlSize(.small)
            })
    }

    private func deepBox(session: MeetingSession) -> some View {
        RoleBox(
            title: "Deep", accent: Theme.accentDeep, role: .deep, session: session,
            outputText: session.deepAnswer,
            placeholder: "Ask for a detailed/coding answer.",
            headerExtra: { EmptyView() },
            actions: {
                Button("Deep answer") { Task { await session.respondDeep(.answerQuestion) } }
                    .controlSize(.small)
            })
    }

    // MARK: Shared model picker (rail) — same set/pin behavior as the old AIPaneView dropdown

    private func modelOptions(role: CopilotRole, session: MeetingSession) -> [String] {
        let current = session.models[role] ?? ""
        if chatModels.contains(current) { return chatModels }
        return current.isEmpty ? chatModels : [current] + chatModels
    }

    func modelPicker(role: CopilotRole, session: MeetingSession, label: String) -> some View {
        Picker(label, selection: Binding(
            get: { session.models[role] ?? "" },
            set: {
                session.setModel(role, $0)
                ProviderSettings.setModel($0, for: role)
                ProviderSettings.pin(role)   // explicit choice: stop auto-defaulting this pane
            }
        )) {
            ForEach(modelOptions(role: role, session: session), id: \.self) { model in
                Text("\(label) · \(model)").tag(model)
            }
        }
        .labelsHidden().controlSize(.small)
    }

    // MARK: Bindings that carry the original onChange side effects

    private func languageBinding(session: MeetingSession) -> Binding<String> {
        Binding(
            get: { transcriptionLocaleID },
            set: { newValue in
                transcriptionLocaleID = newValue
                ProviderSettings.transcriptionLocaleID = newValue
                // The locale is read only when a transcriber is created (at start). Restart an
                // active session so the new language applies immediately instead of next Listen.
                guard wantsCapture else { return }
                restartForLocaleChange(session: session)
            })
    }

    private func presetBinding(session: MeetingSession) -> Binding<String> {
        Binding(
            get: { presetID },
            set: { newID in
                let oldID = presetID
                presetID = newID
                let preset = PresetCatalog.preset(id: newID)
                let previousTemplate = PresetCatalog.preset(id: oldID).notesTemplate
                ProviderSettings.presetID = newID
                session.personaGuidance = preset.personaGuidance
                // Swap the notes scaffold only when the user hasn't edited it (notes still match the
                // previous preset's template, or are empty).
                if session.notes.isEmpty || session.notes == previousTemplate {
                    session.notes = preset.notesTemplate
                }
            })
    }
}
