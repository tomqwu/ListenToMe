import SwiftUI
import ListenToMeCore

/// A derived reading option on Summary, independent of summary generation and the original record.
@MainActor struct SummaryTranslationPanel: View {
    let translation: SummaryTranslationCoordinator
    @Binding var target: String
    let source: String
    let conversationID: String
    var isGenerating = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !expanded {
                Button("Translate summary", systemImage: "translate") { expanded = true; update() }
                    .accessibilityIdentifier("summaryTranslationOptions")
            } else {
                HStack {
                    Label("Translate summary", systemImage: "translate").font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Close") { translation.cancel(); expanded = false }
                        .accessibilityLabel("Close summary translation").accessibilityIdentifier("closeSummaryTranslation")
                }
                Picker("Translate summary into", selection: $target) {
                    TranslationLanguageChoices(selection: target)
                }.accessibilityIdentifier("summaryTranslationTargetPicker")
                Text("On-device translation keeps the original below. Check translated wording before sharing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let problem = translation.problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                Button("Translate", systemImage: "translate") { update(); translation.request() }
                    .disabled(!translation.canTranslate)
                    .accessibilityIdentifier("translateSummary")
                if translation.isRequested {
                    OnDeviceTranslationStatus(worker: translation.worker, target: target, context: conversationID)
                    if translation.matches(source: source, conversationID: conversationID, target: target), let text = translation.translatedText {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text((OutputLanguage.option(target)?.label ?? target) + " translation")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                ShareLink(item: text) { Label("Share translation", systemImage: "square.and.arrow.up") }
                                    .labelStyle(.iconOnly).accessibilityIdentifier("shareSummaryTranslation")
                            }
                            MarkdownText(text: text).textSelection(.enabled)
                                .accessibilityElement(children: .combine).accessibilityIdentifier("translatedSummary")
                        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("Original summary").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { update() }
            .onChange(of: source) { _, _ in update() }
            .onChange(of: target) { _, _ in update() }
            .onChange(of: isGenerating) { _, _ in update() }
            .onChange(of: conversationID) { _, _ in translation.cancel(); expanded = false; update() }
    }
    private func update() {
        translation.update(source: source, conversationID: conversationID, target: target, isGenerating: isGenerating)
    }
}
