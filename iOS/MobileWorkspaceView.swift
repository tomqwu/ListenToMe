import SwiftUI
import ListenToMeCore

/// The phone's two pages: Live (transcript and Quick Summary) and Summary. Deep is macOS-only (#235).
enum MobileWorkspace: String, CaseIterable {
    case live = "Live", summary = "Summary"
}

struct MobileWorkspaceView<Header: View>: View {
    @Bindable var session: MobileSession
    @Binding var selection: MobileWorkspace
    let chooseModel: (MobileSummaryMode) -> Void
    let accessibilityHeader: () -> Header
    @State private var showQuickStatus = false
    @State private var showTranscript = false
    @State private var showSpeechSettings = false
    @State private var transcriptSelection = TranscriptSelection()   // Select mode (#234)
    @State private var selectingTranscript = false
    /// Selection summaries asked for from the Live panel and from the expanded transcript. Each is
    /// presented from a view that survives layout changes (the panel itself is rebuilt on rotation).
    @State private var panelRequest: MobileSelectionRequest?
    @State private var expandedRequest: MobileSelectionRequest?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            let layout = MeetingWorkspaceLayout.resolve(width: geometry.size.width, height: geometry.size.height,
                                                        accessibilityText: typeSize.isAccessibilitySize)
            if layout == .wide {
                HStack(alignment: .top, spacing: 20) {
                    livePanels(height: geometry.size.height)
                        .frame(width: (geometry.size.width - 20) * 0.52)
                    summaryPanel(.summary)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("wideMeetingWorkspace")
            } else {
                VStack(spacing: 14) {
                    Picker("Workspace", selection: $selection) {
                        ForEach(MobileWorkspace.allCases, id: \.self) { page in
                            Text(page.rawValue).tag(page)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("workspaceTabs")
                    if layout == .twoPane {
                        if selection == .live {
                            HStack(alignment: .top, spacing: 12) {
                                transcriptPanel(compact: true)
                                summaryPanel(.quick, compact: true)
                            }.accessibilityElement(children: .contain).accessibilityIdentifier("twoPaneMeetingWorkspace")
                        } else {
                            summaryPanel(.summary, compact: true)
                        }
                    } else if layout == .scrolling {
                        ScrollView {
                            VStack(spacing: 16) {
                                if typeSize.isAccessibilitySize { accessibilityHeader() }
                                if selection == .live { transcriptPanel(scrolling: true); summaryPanel(.quick, scrolling: true) }
                                else { summaryPanel(.summary, scrolling: true) }
                            }
                        }.accessibilityIdentifier("dashboardScroll")
                    } else if selection == .live {
                        livePanels(height: geometry.size.height - 46)
                    } else {
                        summaryPanel(.summary)
                    }
                }
            }
        }
        .sheet(isPresented: $showTranscript) {
            NavigationStack {
                // The saved audio's player, when there is one (#55), over the selectable transcript (#234).
                MobileSavedAudioTranscript(session: session, selection: $transcriptSelection,
                                           selecting: $selectingTranscript, request: $expandedRequest)
                    .navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if !selectingTranscript && session.segments.contains(where: \.isFinal) {
                            Button("Select", systemImage: "checklist") { selectingTranscript = true }
                                .accessibilityIdentifier("selectExpandedTranscriptLines")
                        }
                        Button("Done") { showTranscript = false }
                    }
            }
            .sheet(item: $expandedRequest) { request in
                MobileSelectionSummarySheet(session: session, request: request).presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $panelRequest) { request in
            MobileSelectionSummarySheet(session: session, request: request).presentationDetents([.medium, .large])
        }
        .onChange(of: showTranscript) { _, shown in if !shown { selectingTranscript = false; transcriptSelection.clear() } }
        .onChange(of: session.id) { selectingTranscript = false; transcriptSelection.clear() }
        .sheet(isPresented: $showSpeechSettings) {
            NavigationStack {
                Form {
                    MobileSpeechCorrectionSettings(ai: session.ai)
                    MobileAISettingsView(ai: session.ai, includeSpeechCorrection: false)
                }
                    .navigationTitle("AI settings").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { showSpeechSettings = false } }
            }
        }
    }

    private func livePanels(height: CGFloat) -> some View {
        VStack(spacing: 16) {
            transcriptPanel().frame(height: min(260, max(160, (height - 16) * 0.34)))
            summaryPanel(.quick).frame(maxHeight: .infinity)
        }
    }

    private func transcriptPanel(scrolling: Bool = false, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !compact { MobileRoleIcon(symbol: "waveform", tint: MobileStyle.transcript) }
                Text("Live transcript").font(compact ? .subheadline.bold() : .headline).foregroundStyle(MobileStyle.ink)
                Spacer()
                if session.state == .recording {
                    Circle().fill(.red).frame(width: 6, height: 6).accessibilityLabel("Recording")
                }
                if session.segments.contains(where: \.isFinal) {
                    // Selecting happens in the full-height transcript, where the selection bar fits (#234).
                    Button("Select lines", systemImage: "checklist") { selectingTranscript = true; showTranscript = true }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(MobileStyle.muted)
                        .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("selectTranscriptLines")
                }
                if compact {
                    Button("Speech correction settings", systemImage: "sparkles") { showSpeechSettings = true }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(MobileStyle.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("speechCorrectionSettings")
                }
                if session.canPlaySavedAudio {
                    Button("Play recording", systemImage: "play.circle") { showTranscript = true }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(MobileStyle.accent)
                        .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("playSavedAudio")
                }
                Button("Expand transcript", systemImage: "arrow.up.left.and.arrow.down.right") { showTranscript = true }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .foregroundStyle(MobileStyle.muted)
                    .frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 4 : 8)
            Rectangle().fill(MobileStyle.line).frame(height: 0.75).padding(.horizontal, 16)
            if !compact {
                Button { showSpeechSettings = true } label: {
                    Label(session.ai.correctTranscript ? session.speechCorrectionStatus : "Improve speech · Set up AI correction",
                          systemImage: session.speechCorrection.working ? "ellipsis" : "sparkles")
                        .font(.caption).lineLimit(scrolling ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                }.buttonStyle(.plain).foregroundStyle(MobileStyle.accent)
                    .accessibilityIdentifier("speechCorrectionSettings")
            }
            if session.allSegments.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(MobileStyle.transcript.opacity(0.6))
                        .accessibilityHidden(true)
                    Text("Start listening and your words will appear here.")
                        .font(.subheadline).foregroundStyle(MobileStyle.muted)
                }.padding(16)
            } else if scrolling {
                // Keep one outer scroll at large text sizes/short heights. Full history has its own reader.
                Text(session.allSegments.last?.text ?? "").font(.body).lineSpacing(4)
                    .lineLimit(4).truncationMode(.head).padding(16)
                    .accessibilityIdentifier("latestTranscriptPreview")
            } else {
                MobileSelectableTranscript(session: session, selection: $transcriptSelection,
                                           selecting: $selectingTranscript, request: $panelRequest, selectable: false,
                                           startSelecting: { showTranscript = true }).id(session.id)
            }
        }.frame(maxWidth: .infinity, maxHeight: scrolling ? nil : .infinity, alignment: .topLeading)
            .modifier(MobileCard())
            .accessibilityElement(children: .contain).accessibilityIdentifier("transcriptPanel")
    }

    private func summaryPanel(_ mode: MobileSummaryMode, scrolling: Bool = false, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryHeader(mode, compact: compact)
            readingArea(scrolling: scrolling) {
                VStack(alignment: .leading, spacing: 12) {
                    if mode == .quick {
                        if compact { autoToggle }

                        Text(session.autoQuickStatus).font(.caption).foregroundStyle(MobileStyle.muted)
                            .accessibilityIdentifier("autoQuickStatus")
                        Button("Status details") { showQuickStatus = true }
                            .font(.caption).accessibilityIdentifier("quickStatusDetails")
                            .alert("Quick Summary status", isPresented: $showQuickStatus) {
                                Button("Copy") { UIPasteboard.general.string = session.quickDiagnostics }
                                Button("Close", role: .cancel) {}
                            } message: { Text(session.quickDiagnostics) }
                        if let error = session.quickSummaryError {
                            Label(error, systemImage: "exclamationmark.circle").font(.caption)
                                .foregroundStyle(.secondary).accessibilityIdentifier("quickSummaryError")
                        }
                        if session.autoQuick && session.ai.provider != .apple {
                            Text("New speech triggers Quick evaluation; related words are batched briefly. "
                                 + "Auto also updates Summary when relevant. Both use the selected "
                                 + "models on \(session.ai.summaryEndpointLabel).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if mode == .summary {
                        Text(session.automaticReviewStatus(mode)).font(.caption).foregroundStyle(MobileStyle.muted)
                            .accessibilityIdentifier("autoReviewStatus-\(mode.rawValue)")
                    }
                    if mode == .summary, let review = session.quickReader.recommendations.first(where: { $0.mode == mode.rawValue }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(session.autoQuick && review.confidence != "low" ? "Automatic review trigger" : "Review suggested",
                                  systemImage: "sparkles").font(.subheadline.weight(.medium))
                            Text(review.reason).font(.caption)
                            Text("AI confidence: \(review.confidence) · Generate when ready.")
                                .font(.caption2).foregroundStyle(MobileStyle.muted)
                        }.foregroundStyle(MobileStyle.tint(for: mode))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("review-suggestion-\(mode.rawValue)")
                    }
                    if session.generatingMode == mode {
                        Label("Updating…", systemImage: "sparkles").font(.caption)
                            .foregroundStyle(MobileStyle.tint(for: mode))
                        MarkdownText(text: session.summaryDraft).textSelection(.enabled)
                    }
                    if session.generatingMode != mode { MobileAnswerNoticeLines(session: session, mode: mode) }
                    let output = session.output(for: mode)
                    if !output.isEmpty {
                        MarkdownText(text: output).font(.body).lineSpacing(3).textSelection(.enabled)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("output-\(mode.rawValue)")
                    } else if session.generatingMode != mode && (mode != .quick || session.quickSummaryError == nil) {
                        MobileOutputPlaceholder(mode: mode)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("output-\(mode.rawValue)")
                    }
                    MobileSuggestedPrompts(session: session, mode: mode)
                    if mode == .summary, !session.earlierDeepAnalysis.isEmpty {
                        MobileEarlierDeepAnalysis(text: session.earlierDeepAnalysis)
                    }
                    if mode == .summary, !session.selectionSummaries.isEmpty {
                        MobileSavedSelectionSummaries(summaries: session.selectionSummaries)
                    }
                    if let reason = session.summaryBlockReason(for: mode), !session.isSummarizing {
                        Text(reason).font(.caption).foregroundStyle(MobileStyle.muted)
                            .accessibilityIdentifier("reason-\(mode.rawValue)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }.frame(maxWidth: .infinity, maxHeight: scrolling ? nil : .infinity, alignment: .topLeading)
            .modifier(MobileCard())
            .accessibilityElement(children: .contain).accessibilityIdentifier("summary-panel-\(mode.rawValue)")
    }

    @ViewBuilder
    private func summaryHeader(_ mode: MobileSummaryMode, compact: Bool) -> some View {
        if compact {
            HStack(spacing: 8) {
                Text(mode.title).font(.subheadline.bold()).foregroundStyle(MobileStyle.ink)
                Spacer(minLength: 0)
                modelButton(mode).frame(maxWidth: 110)
                generateButton(mode)
            }.padding(8)
            Rectangle().fill(MobileStyle.line).frame(height: 0.75).padding(.horizontal, 12)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if typeSize.isAccessibilitySize {
                    HStack {
                        MobileRoleIcon(symbol: MobileStyle.symbol(for: mode), tint: MobileStyle.tint(for: mode))
                        Spacer()
                        generateButton(mode)
                    }
                    Text(mode.title).font(.headline).foregroundStyle(MobileStyle.ink)
                } else {
                    HStack(alignment: .top) {
                        MobileRoleIcon(symbol: MobileStyle.symbol(for: mode), tint: MobileStyle.tint(for: mode))
                        Text(mode.title).font(.headline).foregroundStyle(MobileStyle.ink).padding(.top, 4)
                        Spacer(minLength: 8)
                        generateButton(mode)
                    }
                }
                if typeSize.isAccessibilitySize {
                    modelButton(mode)
                    if mode == .quick { autoToggle }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        modelButton(mode)
                        Spacer(minLength: 0)
                        if mode == .quick { autoToggle.fixedSize() }
                    }
                }
            }.padding(16)
                .background {
                    LinearGradient(colors: [MobileStyle.tint(for: mode).opacity(0.05), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            Rectangle().fill(MobileStyle.line).frame(height: 0.75).padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func generateButton(_ mode: MobileSummaryMode) -> some View {
        if session.generatingMode == mode {
            Button("Cancel", systemImage: "stop.circle") { session.cancelSummary() }
                .labelStyle(.iconOnly).font(.system(size: 20))
                .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Cancel \(mode.title)")
        } else {
            Button { session.requestSummary(for: mode) } label: {
                Image(systemName: session.output(for: mode).isEmpty ? "sparkles" : "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold)).frame(minWidth: 32, minHeight: 32)
            }.buttonStyle(.bordered).controlSize(.small).tint(MobileStyle.tint(for: mode))
                .accessibilityLabel("Generate \(mode.title)")
                .disabled(session.summaryBlockReason(for: mode) != nil)
        }
    }

    private func modelButton(_ mode: MobileSummaryMode) -> some View {
        Button { chooseModel(mode) } label: {
            HStack(spacing: 4) {
                Text(session.ai.provider == .apple ? "Apple Intelligence" :
                     (session.ai.selectedModel(for: mode).isEmpty ? "Choose model" : session.ai.selectedModel(for: mode)))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.caption.weight(.medium)).foregroundStyle(MobileStyle.muted)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(MobileStyle.tint(for: mode).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("panel-model-\(mode.rawValue)")
    }

    private var autoToggle: some View {
        Toggle("Auto", isOn: $session.autoQuick).font(.caption)
            .accessibilityLabel("Auto summaries")
            .accessibilityHint(session.ai.provider != .apple
                ? "New speech triggers Quick evaluation and relevant Summary reviews using their "
                  + "selected models on \(session.ai.summaryEndpointLabel)."
                : "Continuous evaluation requires Ollama, a cloud AI service or an OpenAI-compatible server. "
                  + "Apple Intelligence summaries are available with Refresh.")
    }

    @ViewBuilder
    private func readingArea<Content: View>(scrolling: Bool, @ViewBuilder content: () -> Content) -> some View {
        if scrolling { content() } else { ScrollView { content() } }
    }
}

/// A Deep analysis an earlier version saved with this conversation (#235). iOS no longer generates
/// Deep, so it is shown read-only under the Summary, collapsed, and kept in exports and saved notes.
struct MobileEarlierDeepAnalysis: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            MarkdownText(text: text).font(.callout).lineSpacing(3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                .accessibilityElement(children: .combine).accessibilityIdentifier("earlierDeepAnalysisText")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Earlier deep analysis").font(.subheadline.weight(.medium)).foregroundStyle(MobileStyle.ink)
                Text("Saved with this conversation. Read-only; Deep is available on Mac.")
                    .font(.caption).foregroundStyle(MobileStyle.muted)
            }
        }
        .padding(12)
        .background(MobileStyle.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("earlierDeepAnalysis")
    }
}
