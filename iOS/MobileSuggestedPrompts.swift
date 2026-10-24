import SwiftUI
import ListenToMeCore

/// Context-aware one-tap prompts (#61) under the Quick Summary, with the Ask card that answers a
/// tapped one. Each chip is a literal request of at most 60 characters, shown as plain text; a tap
/// asks the Quick model and the answer appears right here, under Quick, never in a summary. The chips stack
/// vertically so they wrap at phone width and at every Dynamic Type size instead of scrolling sideways.
struct MobileSuggestedPrompts: View {
    let session: MobileSession
    /// The panel showing this view; the chips and the Ask card belong to Quick Summary only.
    let mode: MobileSummaryMode

    var body: some View {
        if mode == .quick {
            VStack(alignment: .leading, spacing: 12) {
                MobileAskCard(ask: session.suggestedAsk)
                chips(session.suggestedPrompts)
            }
        }
    }

    @ViewBuilder
    private func chips(_ prompts: [String]) -> some View {
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggested · from context", systemImage: "sparkles")
                    .font(.caption.weight(.medium)).foregroundStyle(MobileStyle.muted)
                ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                    Button { session.askSuggested(prompt) } label: {
                        Text(verbatim: prompt).font(.subheadline).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            // With the bordered style's padding the chip is at least 44 pt tall.
                            .frame(minHeight: 32, alignment: .leading)
                    }
                    .buttonStyle(.bordered).tint(MobileStyle.accent)
                    .disabled(session.suggestionBlockReason != nil)
                    .accessibilityHint("Asks this question; the answer appears below Quick Summary.")
                    .accessibilityIdentifier("suggestedPrompt-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("suggestedPrompts")
        }
    }
}

/// The answer to a tapped chip (#61): the question in bold, the streamed answer below it, and Close
/// (Cancel while it streams). It is not saved with the conversation.
struct MobileAskCard: View {
    let ask: MobileSuggestedAsk

    var body: some View {
        if let question = ask.question {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: question).font(.subheadline.weight(.bold)).foregroundStyle(MobileStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("suggestedQuestion")
                    Spacer(minLength: 8)
                    Group {
                        if ask.isAnswering {
                            Button("Cancel") { ask.cancel() }.accessibilityIdentifier("cancelSuggestedAsk")
                        } else {
                            Button("Close") { ask.reset() }.accessibilityIdentifier("closeSuggestedAsk")
                        }
                    }.font(.caption).frame(minWidth: 44, minHeight: 44)
                }
                if !ask.answer.isEmpty {
                    MarkdownText(text: ask.answer).font(.body).textSelection(.enabled)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("suggestedAnswer")
                } else if ask.isAnswering {
                    Label("Answering…", systemImage: "ellipsis").font(.caption).foregroundStyle(MobileStyle.accent)
                } else if ask.error == nil {
                    Text("Stopped.").font(.caption).foregroundStyle(MobileStyle.muted)
                }
                if let error = ask.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("suggestedAnswerError")
                }
                if let grounding = ask.grounding {
                    Text(grounding).font(.caption2).foregroundStyle(MobileStyle.muted)
                }
                Text("Not saved with the conversation.").font(.caption2).foregroundStyle(MobileStyle.muted)
            }
            .padding(12)
            .background(MobileStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("suggestedAsk")
        }
    }
}
