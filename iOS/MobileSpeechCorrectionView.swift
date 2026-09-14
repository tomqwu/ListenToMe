import SwiftUI
import ListenToMeCore

struct MobileSpeechCorrectionSettings: View {
    @Bindable var ai: MobileAISettings

    var body: some View {
        Section {
            Toggle("Correct speech with AI", isOn: $ai.correctTranscript)
                .accessibilityIdentifier("correctSpeechToggle")
            Text("When enabled, new completed phrases and nearby transcript text are sent automatically to " +
                 "\(ai.endpointDescription). Audio, notes and files are not sent for correction. " +
                 "Your account's usage limits apply on Ollama Cloud.")
                .font(.footnote).foregroundStyle(.secondary)
            NavigationLink {
                MobileCorrectionModelView(ai: ai)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Speech correction model", systemImage: "bolt.fill")
                    Text(ai.correctionModel.isEmpty ? "Choose a Flash model" : ai.correctionModel)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("choose-correction-model")
            if ai.correctTranscript, let reason = ai.correctionAvailability {
                Text(reason).font(.callout).foregroundStyle(.orange)
            }
        } header: { Text("Intelligent speech correction") } footer: {
            Text("Small edits for likely misheard words. Originals are saved: tap AI corrected to review or restore. " +
                 "AI may misinterpret speech. Existing summaries do not change until their next update.")
        }
    }
}

struct MobileCorrectionModelView: View {
    @Bindable var ai: MobileAISettings

    var body: some View {
        List {
            Section {
                Text("Flash models only. Requests are kept short, with a separate model choice from your summaries.")
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from API") { Task { await ai.refresh() } }
                    .disabled(ai.refreshing)
                if let status = ai.status { Text(status).font(.caption) }
            }
            Section("Available Flash models") {
                ForEach(ai.correctionModels) { model in
                    Button { ai.selectCorrectionModel(model.name) } label: {
                        HStack {
                            Text(model.name).foregroundStyle(.primary)
                            Spacer()
                            if ai.correctionModel == model.name { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                        }
                    }.accessibilityIdentifier("correction-model-\(model.name)")
                }
                if ai.correctionModels.isEmpty { Text("No Flash models loaded. Refresh the API catalog.") }
            }
        }.navigationTitle("Speech correction").navigationBarTitleDisplayMode(.inline)
            .task { if ai.models.isEmpty { await ai.refresh() } }
    }
}

struct MobileSpeechCorrectionReview: View {
    let segment: TranscriptSegment
    let restore: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Apple recognized") { Text(segment.originalText ?? segment.text).textSelection(.enabled) }
                Section("AI corrected") { Text(segment.text).textSelection(.enabled) }
                Section {
                    Button("Restore original", systemImage: "arrow.uturn.backward") { restore(segment.id); dismiss() }
                    Text("Restoring also updates the text used for future summaries. Existing summaries stay as generated.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let model = segment.correctionModel { Text(model).font(.caption).foregroundStyle(.secondary) }
                }
            }.navigationTitle("Speech correction").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}
