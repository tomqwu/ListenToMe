import SwiftUI
import Translation
import ListenToMeCore

/// Shared native controls. Language preparation starts only from an explicit button.
@MainActor struct ConversationLanguageControls: View {
    @Binding var options: ConversationLanguageOptions
    let translation: LiveTranslationCoordinator
    let conversationID: String
    var save: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Live transcript translation", isOn: $options.translateTranscript)
                .accessibilityIdentifier("liveTranslationToggle")
            Picker("Translate into", selection: $options.translationTarget) {
                TranslationLanguageChoices(selection: options.translationTarget)
            }.accessibilityIdentifier("translationTargetPicker")
            Text("Finalized speech is translated beneath the original using on-device language packs. Original text, speakers and audio stay unchanged.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if options.translateTranscript {
                OnDeviceTranslationStatus(worker: translation, target: options.translationTarget, context: conversationID)
            }
        }.onChange(of: options) { _, _ in save() }
    }
}

struct TranslationLanguageChoices: View {
    let selection: String
    var body: some View {
        if OutputLanguage.option(selection) == nil { Text("Unavailable saved language").tag(selection) }
        ForEach(OutputLanguage.all) { language in Text(language.label).tag(language.id) }
    }
}

@MainActor struct OnDeviceTranslationStatus: View {
    let worker: LiveTranslationCoordinator
    let target: String
    let context: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var preparing = false
    @State private var preparationID = UUID()
    @State private var preparationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if preparing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing translation languages…").font(.caption)
                    Button("Cancel") { cancelPreparation() }.accessibilityIdentifier("cancelTranslationPreparation")
                }
            } else if let action = worker.availability.setupAction, worker.preparationSource != nil {
                Text(worker.availability.reason ?? "Prepare the selected languages.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(action, systemImage: "arrow.down.circle") { prepare() }
                    .accessibilityIdentifier("prepareTranslationLanguages")
            } else if let reason = worker.availability.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("translationAvailability")
            } else if worker.isTranslating {
                Text("Translating…").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Translation uses installed on-device languages.").font(.caption).foregroundStyle(.secondary)
            }
            if !worker.problems.isEmpty, !preparing {
                Button("Retry translation", systemImage: "arrow.clockwise") { worker.retry() }
                    .accessibilityIdentifier("retryTranslation")
            }
            if let preparationError {
                Text(preparationError).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("translationPreparationError")
            }
        }
        .onChange(of: target) { _, _ in cancelPreparation(); preparationError = nil }
        .onChange(of: context) { _, _ in cancelPreparation(); preparationError = nil }
        .onChange(of: worker.preparationSource) { old, new in if old != new { cancelPreparation() } }
        .onDisappear { cancelPreparation() }
        .translationTask(configuration) { @Sendable session in
            let requestID = await MainActor.run { preparationID }
            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    guard requestID == preparationID, !Task.isCancelled else { return }
                    preparing = false; configuration = nil; worker.retry()
                }
            } catch {
                await MainActor.run {
                    guard requestID == preparationID, !Task.isCancelled else { return }
                    preparing = false; configuration = nil
                    preparationError = "Language preparation did not complete. Your original text is kept; try Prepare again when ready."
                    worker.retry()
                }
            }
        }
    }
    private func prepare() {
        guard let source = worker.preparationSource, worker.availability.setupAction != nil else { return }
        preparationID = UUID(); preparationError = nil; preparing = true
        configuration = .init(source: .init(identifier: source), target: .init(identifier: target))
    }
    private func cancelPreparation() { preparationID = UUID(); configuration = nil; preparing = false }
}

struct TranslatedTranscriptText: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .accessibilityLabel("Translation: " + text).textSelection(.enabled)
    }
}
