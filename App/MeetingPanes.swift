import SwiftUI
import ListenToMeCore

// MARK: - Shared pane chrome

/// A gently pulsing red dot used as the live-recording indicator.
struct RecordingIndicator: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.35 : 1)
            .scaleEffect(pulsing ? 0.8 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .accessibilityLabel("Recording")
    }
}

/// Centered placeholder shown when a pane has no content: a subtle SF Symbol over secondary text.
struct PaneEmptyState: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - AIPaneView

struct AIPaneView: View {
    let title: String
    let role: CopilotRole
    let session: MeetingSession
    let chatModels: [String]
    let outputText: String
    let placeholder: String
    @State private var atBottom = true
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if !outputText.isEmpty {
                                MarkdownText(text: outputText)
                                    .foregroundStyle(.primary)
                            } else if session.streamingRoles.contains(role) {
                                Text("💭 Thinking…")
                                    .foregroundStyle(.secondary)
                            } else {
                                PaneEmptyState(
                                    systemImage: "bubble.left.and.text.bubble.right",
                                    text: placeholder
                                )
                            }
                        }
                        Color.clear.frame(height: 1).id(MeetingView.scrollBottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Follow the streamed answer only while the user is at the bottom.
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 24
                } action: { _, isAtBottom in atBottom = isAtBottom }
                .onChange(of: outputText) { _, _ in
                    if atBottom { proxy.scrollTo(MeetingView.scrollBottomID, anchor: .bottom) }
                }
            }
            actionButtons()
        }
        .paneCard()
        .padding(Theme.paneSpacing)
        .frame(minHeight: 160)
    }
}
