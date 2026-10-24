import SwiftUI
import ListenToMeCore

/// Shared composer: choosing a preset edits a draft; only Ask or Save performs an action.
struct ConversationPromptEditor: View {
    @Binding var instructions: String
    let suggestions: [String]
    let domain: VocabularyDomain?
    let blockReason: String?
    var allowsDeep = false
    let ask: (String, Bool) -> Void
    let save: () -> Void
    @State private var savedMode = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt").font(.headline)
            Picker("Prompt mode", selection: $savedMode) {
                Text("Ask once").tag(false)
                Text("Summary instructions").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("conversationPromptMode")
            TextField(savedMode ? "How should summaries be written?" : "Ask about this conversation", text: $draft, axis: .vertical)
                .lineLimit(2...6).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("conversationPromptDraft")
                .onChange(of: draft) { _, value in
                    if value.count > ConversationPrompt.maximumLength { draft = String(value.prefix(ConversationPrompt.maximumLength)) }
                }
            Menu("Domain presets") {
                ForEach(VocabularyCatalog.bundled.domains) { value in
                    Button(value.name) { draft = ConversationPrompt.preset(value, saved: savedMode) }
                }
            }.accessibilityIdentifier("conversationPromptPresets")
            if let domain {
                Button("Suggested: \(domain.name)") { draft = ConversationPrompt.preset(domain, saved: savedMode) }
                    .accessibilityIdentifier("conversationPromptDomainSuggestion")
            }
            if !savedMode {
                ForEach(suggestions, id: \.self) { prompt in
                    Button(prompt) { draft = prompt }.font(.caption)
                }
            }
            if savedMode {
                Button("Save instructions") { instructions = ConversationPrompt.normalized(draft); save() }
                    .accessibilityIdentifier("saveConversationInstructions")
                Text("Saved with this conversation. Applies to future summaries; clear and save to remove.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Ask Quick") { ask(ConversationPrompt.normalized(draft), false) }
                        .accessibilityIdentifier("askConversationPrompt")
                    if allowsDeep { Button("Ask Deep") { ask(ConversationPrompt.normalized(draft), true) } }
                }.disabled(ConversationPrompt.normalized(draft).isEmpty || blockReason != nil)
                if let blockReason { Text(blockReason).font(.caption).foregroundStyle(.secondary) }
                Text(allowsDeep ? "Uses your selected model and conversation context. The answer appears in the chosen pane."
                     : "Uses your selected Quick model and conversation context. The answer appears below and in Quick.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: savedMode) { _, value in draft = value ? instructions : "" }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversationPromptEditor")
    }
}
