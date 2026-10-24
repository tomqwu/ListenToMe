import SwiftUI
import ListenToMeCore

/// Context-aware one-tap prompts (#61) under the Quick Summary. Each chip is a literal request of at
/// most 60 characters, shown as plain text; a tap asks the Deep model and opens the Deep tab, where
/// `MobileSuggestedAnswer` shows the answer. The chips stack vertically so they wrap at phone width
/// and at every Dynamic Type size instead of scrolling sideways.
struct MobileSuggestedPrompts: View {
    let session: MobileSession
    /// The panel showing this view; the chips belong to Quick Summary only.
    let mode: MobileSummaryMode
    /// Called after a tap that was actually sent, so the workspace can show the answer.
    let didAsk: () -> Void

    var body: some View {
        let prompts = mode == .quick ? session.suggestedPrompts : []
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggested · from context", systemImage: "sparkles")
                    .font(.caption.weight(.medium)).foregroundStyle(MobileStyle.muted)
                ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                    Button {
                        if session.askSuggested(prompt) { didAsk() }
                    } label: {
                        Text(verbatim: prompt).font(.subheadline).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            // With the bordered style's padding the chip is at least 44 pt tall.
                            .frame(minHeight: 32, alignment: .leading)
                    }
                    .buttonStyle(.bordered).tint(MobileStyle.deep)
                    .disabled(session.suggestionBlockReason != nil)
                    .accessibilityHint("Asks the Deep model this question about the conversation.")
                    .accessibilityIdentifier("suggestedPrompt-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("suggestedPrompts")
        }
    }
}

/// The answer to a tapped chip, at the top of the Deep panel and separate from Deep Summary (#61):
/// the question in plain text, then the streamed answer. It is not saved with the conversation.
struct MobileSuggestedAnswer: View {
    let session: MobileSession
    let mode: MobileSummaryMode

    var body: some View {
        let ask = session.suggestedAsk
        if mode == .deep, let question = ask.question {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("You asked", systemImage: "sparkles")
                        .font(.caption.weight(.medium)).foregroundStyle(MobileStyle.muted)
                    Spacer()
                    Group {
                        if ask.isAnswering {
                            Button("Cancel") { ask.cancel() }.accessibilityIdentifier("cancelSuggestedAsk")
                        } else {
                            Button("Close") { ask.reset() }.accessibilityIdentifier("closeSuggestedAsk")
                        }
                    }.font(.caption).frame(minHeight: 44)
                }
                Text(verbatim: question).font(.subheadline.weight(.semibold)).foregroundStyle(MobileStyle.ink)
                    .accessibilityIdentifier("suggestedQuestion")
                if !ask.answer.isEmpty {
                    MarkdownText(text: ask.answer).font(.body).textSelection(.enabled)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("suggestedAnswer")
                } else if ask.isAnswering {
                    Label("Answering…", systemImage: "ellipsis").font(.caption).foregroundStyle(MobileStyle.deep)
                } else if ask.error == nil {
                    Text("Stopped.").font(.caption).foregroundStyle(MobileStyle.muted)
                }
                if let error = ask.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("suggestedAnswerError")
                }
                Text("Not saved with the conversation; Deep Summary is unchanged.")
                    .font(.caption2).foregroundStyle(MobileStyle.muted)
            }
            .padding(12)
            .background(MobileStyle.deep.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("suggestedAsk")
        }
    }
}
