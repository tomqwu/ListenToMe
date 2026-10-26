import SwiftUI
import ListenToMeCore

/// Context-aware one-tap prompts (#61), shown above the Quick pane's fixed actions. They come from
/// the Auto evaluator's own pass, so the row is absent with Auto or AI off. A tap sends the literal
/// text through Quick (or Deep, from the context menu); nothing is ever sent by itself.
struct SuggestedPromptChips: View {
    let session: MeetingSession

    var body: some View {
        let prompts = session.suggestedPrompts
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label("Suggested · from context", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(Theme.ink2)
                FlowLayout(spacing: 7) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button(prompt) { session.requestSuggested(prompt) }
                            .buttonStyle(.bordered).tint(Theme.accent)
                            .help("Ask Quick: \(prompt)")
                            .contextMenu {
                                Button("Ask in Quick") { session.requestSuggested(prompt) }
                                Button("Ask in Deep") { session.requestSuggested(prompt, deep: true) }
                            }
                    }
                }
                .controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Suggested prompts")
        }
    }
}
