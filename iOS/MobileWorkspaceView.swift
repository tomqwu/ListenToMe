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
    }

    private func livePanels(height: CGFloat) -> some View {
        VStack(spacing: 16) {
            transcriptPanel.frame(height: max(160, (height - 16) * 0.50))
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
            }.padding(16)
            Divider().padding(.horizontal, 16)
            readingArea {
                if session.allSegments.isEmpty {
                    emptyState("Nothing recorded yet", detail: "Start listening and your words will appear here.", icon: "waveform")
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(session.allSegments) { segment in
                            VStack(alignment: .leading, spacing: 5) {
                                if !segment.isFinal {
                                    Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(.indigo)
                                }
                                Text(segment.text).font(.body).lineSpacing(4).textSelection(.enabled)
                                    .foregroundStyle(segment.isFinal ? .primary : .secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(16)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: stacked ? nil : .infinity, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
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
                HStack(alignment: .center, spacing: 10) {
                    Button { chooseModel(mode) } label: {
                        HStack(spacing: 4) {
                            Text(session.ai.provider == .apple ? "Apple Intelligence" :
                                 (session.ai.selectedModel(for: mode).isEmpty ? "Choose model" : session.ai.selectedModel(for: mode)))
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Image(systemName: "chevron.down").font(.caption2)
                        }.font(.caption).foregroundStyle(.indigo)
                    }.buttonStyle(.plain).accessibilityIdentifier("panel-model-\(mode.rawValue)")
                    Spacer(minLength: 0)
                    if mode == .quick {
                        Toggle("Auto", isOn: $session.autoQuick).font(.caption).fixedSize()
                            .accessibilityLabel("Auto Quick Summary")
                            .accessibilityHint(session.ai.provider == .ollama
                                ? "Automatically sends notes and transcript to Ollama Cloud while listening."
                                : "Automatically summarizes on this device while listening.")
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

    @ViewBuilder
    private func readingArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if stacked { content() } else { ScrollView { content() } }
    }

    private func emptyState(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tertiary)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
    }
}
