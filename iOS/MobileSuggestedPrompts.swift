import SwiftUI
import ListenToMeCore

/// Context-aware one-tap prompts (#61) under the Quick Summary. Each chip is a literal request of at
/// most 60 characters; a tap opens Deep and sends it there. The chips stack vertically so they wrap
/// at phone width and at every Dynamic Type size instead of scrolling sideways.
struct MobileSuggestedPrompts: View {
    let session: MobileSession
    /// The panel showing this view; the chips belong to Quick Summary only.
    let mode: MobileSummaryMode
    /// Called after a tap, so the workspace can show the Deep answer. Chips are disabled while a tap
    /// could not be sent.
    let didAsk: () -> Void

    var body: some View {
        let prompts = mode == .quick ? session.suggestedPrompts : []
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggested · from context", systemImage: "sparkles")
                    .font(.caption.weight(.medium)).foregroundStyle(MobileStyle.muted)
                ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                    Button {
                        session.askSuggested(prompt)
                        didAsk()
                    } label: {
                        Text(prompt).font(.subheadline).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 30, alignment: .leading)
                    }
                    .buttonStyle(.bordered).tint(MobileStyle.deep)
                    .disabled(session.suggestionBlockReason != nil)
                    .accessibilityHint("Asks Deep Summary this question about the conversation.")
                    .accessibilityIdentifier("suggestedPrompt-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("suggestedPrompts")
        }
    }
}
