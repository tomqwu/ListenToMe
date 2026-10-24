import SwiftUI
import ListenToMeCore

/// Review is mandatory: a new recognition pass can differ, omit speech, or lose inferred speaker names.
struct RetranscriptionView: View {
    let original: SessionRecord
    let library: SavedAudioLibrary
    let recognizers: [String: SavedAudioRetranscription.Recognize]
    let terms: (String) -> [String]
    let apply: (ConversationRetranscription) throws -> Void
    @State private var draft = SavedAudioRetranscription()
    @State private var language: String
    @State private var engine = "Apple on-device"
    @State private var applyError: String?
    @Environment(\.dismiss) private var dismiss

    init(original: SessionRecord, library: SavedAudioLibrary,
         recognizers: [String: SavedAudioRetranscription.Recognize], terms: @escaping (String) -> [String],
         apply: @escaping (ConversationRetranscription) throws -> Void) {
        self.original = original; self.library = library; self.recognizers = recognizers
        self.terms = terms; self.apply = apply
        _language = State(initialValue: original.conversationLanguages.current ?? Locale.current.identifier(.bcp47))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Re-transcribe saved audio").font(.headline)
                Spacer()
                Button(draft.isRunning ? "Cancel" : "Keep original") { draft.cancel(); dismiss() }
                    .accessibilityIdentifier("keepOriginalTranscript")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Audio stays on this device. A speech model may download on first use. Review the new transcript before replacing the original.")
                    Picker("Language", selection: $language) {
                        let groups = SpeechLanguageCatalog.shared.groups(selected: language, label: languageLabel)
                        ForEach(groups.installed + groups.downloadable, id: \.self) { value in
                            Text(languageLabel(value)).tag(value)
                        }
                    }.accessibilityIdentifier("retranscriptionLanguage").disabled(draft.isRunning)
                    if recognizers.count > 1 {
                        Picker("Transcriber", selection: $engine) {
                            ForEach(recognizers.keys.sorted(), id: \.self) { Text($0).tag($0) }
                        }.disabled(draft.isRunning)
                    }
                    Text("Replacing removes all original transcript lines, including lines with no saved audio. Speaker names and speech corrections are reset. Notes, attachments and summaries are kept; review summaries against the new transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                    if draft.isRunning {
                        ProgressView(draft.progress).accessibilityIdentifier("retranscriptionProgress")
                    } else if let preview = draft.preview {
                        Text("New transcript · \(preview.segments.count) \(preview.segments.count == 1 ? "line" : "lines")").font(.headline)
                        ForEach(preview.segments) { line in
                            Text("\(line.speakerLabel): \(line.text)").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Replace transcript") {
                            do { try apply(preview); dismiss() }
                            catch { applyError = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("replaceTranscript")
                    } else {
                        Button("Re-transcribe") {
                            applyError = nil
                            guard let recognize = recognizers[engine] else { return }
                            draft.start(original: original, library: library, language: language,
                                        terms: terms(language), recognize: recognize)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("startRetranscription")
                    }
                    if let message = applyError ?? draft.error {
                        Text(message).foregroundStyle(.red).accessibilityIdentifier("retranscriptionError")
                    }
                }
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 600, height: 600)
        #endif
        .task { await SpeechLanguageCatalog.shared.load() }
        .onChange(of: language) { _, _ in draft.cancel(); applyError = nil }
        .onChange(of: engine) { _, _ in draft.cancel(); applyError = nil }
        .onDisappear { draft.cancel() }
        .interactiveDismissDisabled(draft.isRunning)
    }

    private func languageLabel(_ value: String) -> String {
        Locale.current.localizedString(forIdentifier: value) ?? value
    }
}

extension LocalAudioFileTranscriber {
    @MainActor
    static func recognize(url: URL, run: SavedAudioRun, language: String, terms: [String]) async throws -> [TranscriptSegment] {
        let reader = LocalAudioFileTranscriber(source: run.source)
        reader.setContextualStrings(terms)
        var lines: [TranscriptSegment] = []
        try await reader.transcribe([LocalAudioChunk(index: run.index, url: url, startOffset: 0,
                                                     duration: run.duration ?? 0)], locale: Locale(identifier: language)) {
            lines.append($0)
        }
        return lines
    }
}
