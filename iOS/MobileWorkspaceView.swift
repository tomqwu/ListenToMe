import SwiftUI
import ListenToMeCore

enum MobileWorkspace: String, CaseIterable {
    case live = "Live", summary = "Summary", deep = "Deep"
    var mode: MobileSummaryMode { self == .summary ? .summary : .deep }
}

struct MobileWorkspaceView<Header: View>: View {
    @Bindable var session: MobileSession
    @Binding var selection: MobileWorkspace
    let chooseModel: (MobileSummaryMode) -> Void
    let accessibilityHeader: () -> Header
    @State private var showTranscript = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSize
    private var stacked: Bool { typeSize.isAccessibilitySize || verticalSize == .compact }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 && geometry.size.height >= 600 && !stacked {
                HStack(alignment: .top, spacing: 20) {
                    livePanels(height: geometry.size.height)
                        .frame(width: (geometry.size.width - 20) * 0.52)
                    VStack(spacing: 16) {
                        Picker("Review", selection: Binding(get: { selection == .live ? .deep : selection },
                                                            set: { selection = $0 })) {
                            Text("Summary").tag(MobileWorkspace.summary)
                            Text("Deep Summary").tag(MobileWorkspace.deep)
                        }.pickerStyle(.segmented).accessibilityIdentifier("reviewTabs")
                        summaryPanel(selection == .summary ? .summary : .deep)
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("wideMeetingWorkspace")
            } else {
                VStack(spacing: 14) {
                    Picker("Workspace", selection: $selection) {
                        ForEach(MobileWorkspace.allCases, id: \.self) { page in
                            Text(page.rawValue).tag(page)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("workspaceTabs")
                    if stacked {
                        ScrollView {
                            VStack(spacing: 16) {
                                if typeSize.isAccessibilitySize { accessibilityHeader() }
                                if selection == .live { transcriptPanel; summaryPanel(.quick) }
                                else { summaryPanel(selection.mode) }
                            }
                        }.accessibilityIdentifier("dashboardScroll")
                    } else if selection == .live {
                        livePanels(height: geometry.size.height - 46)
                    } else {
                        summaryPanel(selection.mode)
                    }
                }
            }
        }
        .sheet(isPresented: $showTranscript) {
            NavigationStack {
                MobileTranscriptReader(segments: session.allSegments, scrollIdentifier: "expandedTranscriptScroll")
                    .id(session.id)
                    .navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { showTranscript = false } }
            }
        }
    }

    private func livePanels(height: CGFloat) -> some View {
        VStack(spacing: 16) {
            transcriptPanel.frame(height: min(260, max(160, (height - 16) * 0.34)))
            summaryPanel(.quick).frame(maxHeight: .infinity)
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Live transcript", systemImage: "waveform").font(.headline)
                Spacer()
                if session.state == .recording {
                    Circle().fill(.red).frame(width: 6, height: 6).accessibilityLabel("Recording")
                }
                Button("Expand transcript", systemImage: "arrow.up.left.and.arrow.down.right") { showTranscript = true }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 16).padding(.vertical, 8)
            Divider().padding(.horizontal, 16)
            if session.allSegments.isEmpty {
                Text("Start listening and your words will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
            } else if stacked {
                // Keep one outer scroll at large text sizes/short heights. Full history has its own reader.
                Text(session.allSegments.last?.text ?? "").font(.body).lineSpacing(4)
                    .lineLimit(4).truncationMode(.head).padding(16)
                    .accessibilityIdentifier("latestTranscriptPreview")
            } else {
                MobileTranscriptReader(segments: session.allSegments).id(session.id)
            }
        }.frame(maxWidth: .infinity, maxHeight: stacked ? nil : .infinity, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain).accessibilityIdentifier("transcriptPanel")
    }

    private func summaryPanel(_ mode: MobileSummaryMode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(mode.title).font(.headline)
                    Spacer(minLength: 8)
                    if session.generatingMode == mode {
                        Button("Cancel", systemImage: "stop.circle") { session.cancelSummary() }
                            .labelStyle(.iconOnly).accessibilityLabel("Cancel \(mode.title)")
                    } else {
                        Button { session.requestSummary(for: mode) } label: {
                            Image(systemName: session.output(for: mode).isEmpty ? "sparkles" : "arrow.clockwise")
                                .frame(minWidth: 32, minHeight: 28)
                        }.buttonStyle(.bordered).controlSize(.small)
                            .accessibilityLabel("Generate \(mode.title)")
                            .disabled(session.summaryBlockReason(for: mode) != nil)
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
            Divider().padding(.horizontal, 16)
            readingArea {
                VStack(alignment: .leading, spacing: 12) {
                    if session.generatingMode == mode {
                        Label("Updating…", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                        MarkdownText(text: session.summaryDraft).textSelection(.enabled)
                    }
                    let output = session.output(for: mode)
                    if !output.isEmpty {
                        MarkdownText(text: output).font(.body).lineSpacing(3).textSelection(.enabled)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("output-\(mode.rawValue)")
                    } else if session.generatingMode != mode {
                        Text(mode == .quick ? "Key points, as the conversation unfolds." :
                             (mode == .summary ? "The key points, decisions and next steps." : "A closer look at decisions, risks and open questions."))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("output-\(mode.rawValue)")
                    }
                    if let reason = session.summaryBlockReason(for: mode), !session.isSummarizing {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("reason-\(mode.rawValue)")
                    } else if mode == .quick && session.autoQuick {
                        Text(session.ai.provider == .ollama ? "Auto sends notes and transcript to Ollama Cloud." :
                             (session.state == .recording ? "Updates automatically while you listen." : "Auto updates when listening starts."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }.frame(maxWidth: .infinity, maxHeight: stacked ? nil : .infinity, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain).accessibilityIdentifier("summary-panel-\(mode.rawValue)")
    }

    private func modelButton(_ mode: MobileSummaryMode) -> some View {
        Button { chooseModel(mode) } label: {
            HStack(spacing: 4) {
                Text(session.ai.provider == .apple ? "Apple Intelligence" :
                     (session.ai.selectedModel(for: mode).isEmpty ? "Choose model" : session.ai.selectedModel(for: mode)))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.caption).foregroundStyle(.indigo)
        }.buttonStyle(.plain).accessibilityIdentifier("panel-model-\(mode.rawValue)")
    }

    private var autoToggle: some View {
        Toggle("Auto", isOn: $session.autoQuick).font(.caption)
            .accessibilityLabel("Auto Quick Summary")
            .accessibilityHint(session.ai.provider == .ollama
                ? "Automatically sends notes and transcript to Ollama Cloud while listening."
                : "Automatically summarizes on this device while listening.")
    }

    @ViewBuilder
    private func readingArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if stacked { content() } else { ScrollView { content() } }
    }
}
