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
        let runningEngine = session.isTranscribingFile ? "speechAnalyzer" : activeEngine
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RailRecStatus(isRunning: session.isRunning, isPreparing: session.isPreparing,
                              elapsed: elapsedLabel)
                AudioLevelMeters(session: session)

                railSection("Engine") {
                    Text(CommandCenterLabels.engine(active: runningEngine,
                                                    saved: ProviderSettings.transcriptionEngine))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                        .help(runningEngine == nil
                              ? "The engine the next Start listening will use"
                              : "The engine this transcription is using — an engine change applies at the next Start")
                    TranscriptionLanguagePicker(selection: languageBinding(session: session))
                    TranscriptionComputeInfo(engine: runningEngine ?? ProviderSettings.transcriptionEngine,
                                             isRunning: runningEngine != nil,
                                             isPreparing: session.isPreparing)
                }

                railSection("Languages") {
                    ConversationLanguageControls(options: $session.languageOptions,
                        translation: session.liveTranslation, conversationID: currentSessionID,
                        save: { _ = checkpoint() })
                }

                railSection("Automatic AI") {
                    Toggle("Auto summaries", isOn: Binding(get: { session.autoSummaryEnabled }, set: {
                        session.autoSummaryEnabled = $0
                        UserDefaults.standard.set($0, forKey: "autoQuickSummary")
                    })).controlSize(.small)
                    Text(session.autoQuickStatus).font(.caption).foregroundStyle(.secondary)
                    Text("New speech triggers Quick evaluation. Auto also runs relevant Summary and Deep reviews; manual controls remain available.")
                        .font(.caption2).foregroundStyle(.secondary)
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

                if ProviderSettings.speakerDiarizationEnabled { speakersRailSection() }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 180, idealWidth: 210, maxWidth: 360)
        .background(Theme.windowBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }

    /// Experimental "Speakers" rail section: an on-demand button that diarizes the captured Others
    /// channel into distinct voices. Shown whenever the experimental setting is enabled (so it's
    /// discoverable), but the button is only usable when the current/most-recent run actually attached
    /// the Others sink — i.e. the setting was on when that run pressed Listen. Toggling the setting on
    /// mid-run does NOT enable it, because this run's capture was built with `othersSink: nil` and its
    /// buffer is empty/stale.
    private func speakersRailSection() -> some View {
        railSection("Speakers") {
            Button { identifySpeakers() } label: {
                Label("Speakers / edit names", systemImage: "person.2.wave.2")
            }
            .controlSize(.small)
            .disabled(!diarizationSinkAttached)
            .help(diarizationSinkAttached
                  ? "View automatic speaker identification and edit names"
                  : "Press Start listening to start capturing speaker audio.")
            // One-line status when automatic identification has stopped (e.g. the on-device models
            // could not be downloaded) — otherwise this was only visible inside the sheet (#109).
            if let speakerStatus {
                Text(speakerStatus).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
    /// Read from the store's incrementally maintained counters: rescanning every utterance on each
    /// render cost O(transcript) once a second while the elapsed timer ticked (issue #116).
    private var youCount: Int { store.youCount }
    private var othersCount: Int { store.othersCount }
    /// Explicit ~chars/4 estimate (labeled "~tok"), never a fabricated exact count.
    private var approxTokens: Int { store.transcriptCharacterCount / 4 }

    // MARK: Center transcript

    /// "idle" when stopped, "preparing" while the speech model is still warming, otherwise
    /// "live · N src". The rule lives in Core (`TranscriptStatusLabel`) so it is unit-tested.
    func transcriptStatusLabel(session: MeetingSession) -> String {
        TranscriptStatusLabel.text(isRunning: session.isRunning, isPreparing: session.isPreparing,
                                   sources: Set(store.utterances.map(\.source)).count)
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
        .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity)
        .modifier(MacAddTermPresenter(vocabulary: vocabulary, apply: applyVocabulary))
        .background(Theme.cardBackground)
        .overlay(Rectangle().fill(Theme.line).frame(width: 1), alignment: .trailing)
    }

    private func transcriptScroll(session: MeetingSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.utterances.isEmpty && store.partial == nil {
                        PaneEmptyState(
                            systemImage: "waveform",
                            text: "Press Start listening to start transcribing the conversation.")
                    }
                    ForEach(store.presentedUtterances) { transcriptRow(for: $0) }
                    ForEach([SpeakerSource.you, .others], id: \.self) { source in
                        if let partial = store.partials[source] { transcriptRow(for: partial).opacity(0.7) }
                    }
                    Color.clear.frame(height: 1).id(Self.scrollBottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .task(id: TranscriptScrollKey(revision: store.revision, you: store.partials[.you],
                                          others: store.partials[.others])) {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                if transcriptFollow.shouldScroll { proxy.scrollTo(Self.scrollBottomID, anchor: .bottom) }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, atEnd in transcriptFollow.geometryChanged(atEnd: atEnd) }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let target = max(0, geometry.contentSize.height - geometry.containerSize.height
                                 + geometry.contentInsets.bottom)
                return abs(geometry.contentOffset.y - target) > 2 ? geometry.contentSize.height.rounded() : 0
            } action: { _, displaced in
                guard displaced > 0, transcriptFollow.shouldScroll else { return }
                transcriptScrollWork.start(load: { await Task.yield() }, apply: { _ in
                    if transcriptFollow.shouldScroll { proxy.scrollTo(Self.scrollBottomID, anchor: .bottom) }
                })
            }
            .onScrollPhaseChange { _, phase, context in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    transcriptFollow.beginUserScroll()
                } else if phase == .idle && transcriptFollow.userScrolling {
                    let geometry = context.geometry
                    transcriptFollow.endUserScroll(atEnd:
                        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !transcriptFollow.following {
                    Button("Latest", systemImage: "arrow.down") {
                        transcriptFollow.latest()
                        proxy.scrollTo(Self.scrollBottomID, anchor: .bottom)
                    }.buttonStyle(.bordered).padding(4)
                        .accessibilityLabel("Jump to latest transcript")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func transcriptRow(for seg: TranscriptSegment) -> some View {
        EditableTranscriptRow(segment: seg, speakerLabel: speakerRowLabel(for: seg),
            copyTranscript: {
                let lines = store.presentedUtterances + [SpeakerSource.you, .others].compactMap { store.partials[$0] }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.map { "\($0.speakerLabel): \($0.text)" }
                    .joined(separator: "\n"), forType: .string)
            }, edit: { editTranscriptLine(seg, text: $0) },
            delete: { deleteTranscriptLine(seg) },
            addTerm: { vocabulary.termSourceLine = seg.text }, translatedText: session.liveTranslation.text(for: seg),
            renameSpeaker: { name in
                guard let id = seg.speakerID,
                      store.utterances.contains(where: { $0.id == seg.id && $0.speakerID == id }) else { return }
                renameSpeaker(id: id, name: name)
            })
    }

    /// Channel/speaker label for a transcript row: "YOU" for the mic; for the Others channel the
    /// resolved "SPEAKER N" (uppercased) when "Identify speakers" has labeled this line, else "OTHERS".
    private func speakerRowLabel(for seg: TranscriptSegment) -> String {
        seg.speakerLabel.uppercased()
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
            ConversationPromptEditor(instructions: Binding(get: { session.summaryInstructions },
                set: { session.summaryInstructions = $0 }), suggestions: session.suggestedPrompts,
                domain: vocabulary.banner(for: currentSessionID)?.domain,
                blockReason: session.aiEnabled ? nil : (modelStatus.isEmpty ? "Turn AI on to ask." : modelStatus),
                allowsDeep: true,
                ask: { prompt, deep in session.requestSuggested(prompt, deep: deep) },
                save: { _ = checkpoint(force: true) })
                .id(currentSessionID)
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
            title: "Summary", accent: Theme.others, role: .listener, session: session,
            outputText: session.listenerSummary,
            placeholder: "Generate a full summary and open items when ready.",
            headerExtra: {
                // Refreshing with nothing new re-summarizes an empty evidence block and can reword
                // or drop items from the record already on screen, so it is disabled until new
                // speech arrives (issue #137).
                Button("Refresh") { session.requestListenerRefresh() }
                    .controlSize(.small)
                    .disabled(!session.aiEnabled || !session.hasUnsummarizedSpeech)
                    .help(session.hasUnsummarizedSpeech
                          ? "Summarize the speech that has not been summarized yet"
                          : "Everything said so far is already summarized.")
            },
            actions: { reviewSuggestion("summary", session: session) })
    }

    private func quickBox(session: MeetingSession) -> some View {
        RoleBox(
            title: "Quick Summary", accent: Theme.accent, role: .quick, session: session,
            outputText: session.quickSuggestion,
            placeholder: "With Proactive on, a question from Others is answered here automatically. "
                + "Enable Auto while listening, or request a recap.",
            headerExtra: {
                // Answers a question from Others automatically, without waiting for a button or the
                // hotkey. Independent of "Auto summaries" (the periodic recap) — see
                // docs/SHARED-LIVE-SUMMARY.md.
                Toggle("Proactive", isOn: Binding(get: { session.proactiveEnabled }, set: {
                    session.proactiveEnabled = $0
                    UserDefaults.standard.set($0, forKey: MeetingView.proactiveDefaultsKey)
                }))
                .toggleStyle(.checkbox).controlSize(.small)
                .help("Answer automatically when the other party asks a question")
                // The automatic recap keeps updating behind a generated answer; this returns to it.
                if session.quickAnswerOverridesRecap {
                    Button("Show recap") { session.dismissQuickAnswer() }
                        .controlSize(.small)
                }
            },
            actions: {
                SuggestedPromptChips(session: session)
                FlowLayout(spacing: 7) {
                    Button("What should I answer?") {
                        session.requestQuick(.answerQuestion)
                    }
                    Button("Recap so far") { session.requestQuick(.recap) }
                    Button("Follow-up") { session.requestQuick(.followUp) }
                    Button("Action items") { session.requestQuick(.actionItems) }
                    Button("Clarify simply") { session.requestQuick(.clarify) }
                    Button("Counterpoint") { session.requestQuick(.counterpoint) }
                    Button("Key terms") { session.requestQuick(.keyTerms) }
                    Button("Draft reply") { session.requestQuick(.draftReply) }
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
                reviewSuggestion("deep", session: session)
                Button("Deep answer") { session.requestDeep(.answerQuestion) }
                    .controlSize(.small)
            })
    }

    @ViewBuilder
    private func reviewSuggestion(_ mode: String, session: MeetingSession) -> some View {
        if let reviewMode = AutomaticReviewMode(rawValue: mode) {
            Text(session.automaticReviewStatus(reviewMode)).font(.caption).foregroundStyle(.secondary)
        }
        if let review = session.quickReader.recommendations.first(where: { $0.mode == mode }) {
            Text("Suggested review · \(review.confidence) confidence: \(review.reason)")
                .font(.caption).foregroundStyle(.secondary)
        }
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
                // The "choose a model for each pane" prompt (#52) clears once every pane has one.
                if ProviderSettings.aiMode == .openAI || ProviderSettings.aiMode == .cloudAI,
                   CopilotRole.allCases.allSatisfy({ !(session.models[$0] ?? "").isEmpty }) { modelStatus = "" }
            }
        )) {
            ForEach(modelOptions(role: role, session: session), id: \.self) { model in
                let modelLabel = ProviderSettings.aiMode == .local
                    ? localOllamaReadiness?.label(for: model) ?? "\(model) (not verified)" : model
                Text("\(label) · \(modelLabel)").tag(model)
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
                applyVocabulary()   // recognition and prompt terms follow the language, even while idle (#238)
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
                applyVocabulary()   // the preset persona plus the active vocabularies (issue #222)
                // Swap the notes scaffold only when the user hasn't edited it (notes still match the
                // previous preset's template, or are empty).
                if session.notes.isEmpty || session.notes == previousTemplate {
                    session.notes = preset.notesTemplate
                }
            })
    }
}

private struct TranscriptScrollKey: Equatable {
    let revision: Int
    let you: TranscriptSegment?
    let others: TranscriptSegment?
}
