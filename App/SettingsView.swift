import SwiftUI
import ListenToMeCore

/// UserDefaults-backed model selection. Ollama-only.
enum ProviderSettings {
    static var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.1" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }
    static var transcriptionEngine: String {
        get { UserDefaults.standard.string(forKey: "transcriptionEngine") ?? "speechAnalyzer" }
        set { UserDefaults.standard.set(newValue, forKey: "transcriptionEngine") }
    }
}

struct SettingsView: View {
    let router: ModelRouter
    @Environment(\.dismiss) private var dismiss

    @State private var engine: String
    @State private var ollamaModel: String
    @State private var validationError: String?
    @State private var ollamaModels: [String] = []
    @State private var loadingModels = false

    init(router: ModelRouter) {
        self.router = router
        _engine = State(initialValue: ProviderSettings.transcriptionEngine)
        _ollamaModel = State(initialValue: ProviderSettings.ollamaModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Settings").font(.title2).bold()

            Picker("Transcription engine", selection: $engine) {
                Text("SpeechAnalyzer (macOS 26, dual-channel)").tag("speechAnalyzer")
                Text("SpeechRecognizer (legacy)").tag("speechRecognizer")
            }
            Text(
                "SpeechAnalyzer transcribes both channels concurrently and downloads its model on first use; " +
                "SpeechRecognizer is the fallback. Changing this takes effect when you next press Listen."
            )
            .font(.caption).foregroundStyle(.secondary)

            ollamaModelSection

            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { if save() { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await loadOllamaModels() }
    }

    @ViewBuilder
    private var ollamaModelSection: some View {
        if ollamaModels.isEmpty {
            TextField("Model", text: $ollamaModel)
                .textFieldStyle(.roundedBorder)
            HStack(alignment: .top) {
                Text(loadingModels
                     ? "Fetching installed models…"
                     : "Ollama not reachable at http://localhost:11434 — start it, or type a model name.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await loadOllamaModels() } }
                    .font(.caption)
                    .disabled(loadingModels)
            }
        } else {
            // Build the picker options: installed models + the saved value if missing from list.
            let options: [String] = ollamaModels.contains(ollamaModel)
                ? ollamaModels
                : [ollamaModel] + ollamaModels
            Picker("Model", selection: $ollamaModel) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            HStack(alignment: .top) {
                Text(
                    "Models come from your local Ollama — includes local models and " +
                    "Ollama-cloud models (e.g. deepseek-v4-flash:cloud)."
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await loadOllamaModels() } }
                    .font(.caption)
                    .disabled(loadingModels)
            }
        }
    }

    private func loadOllamaModels() async {
        loadingModels = true
        let names = await OllamaModels.chatModels()
        ollamaModels = names
        // If the current saved model isn't chat-capable / installed, pre-select a better default.
        if !names.isEmpty, !names.contains(ollamaModel),
           let preferred = OllamaModels.preferredChatModel(from: names) {
            ollamaModel = preferred
        }
        loadingModels = false
    }

    private func save() -> Bool {
        let model = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            validationError = "Enter an Ollama model name (e.g. llama3.1)."
            return false
        }
        ProviderSettings.ollamaModel = model
        router.register(OllamaProvider(model: model))
        router.setActive("ollama")
        ProviderSettings.transcriptionEngine = engine   // only persisted on a successful save
        return true
    }
}
