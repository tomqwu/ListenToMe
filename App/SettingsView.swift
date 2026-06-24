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
    static func model(for role: CopilotRole) -> String {
        UserDefaults.standard.string(forKey: "model_\(role.rawValue)") ?? ollamaModel
    }
    static func setModel(_ model: String, for role: CopilotRole) {
        UserDefaults.standard.set(model, forKey: "model_\(role.rawValue)")
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var engine: String
    @State private var ollamaKey: String

    init() {
        _engine = State(initialValue: ProviderSettings.transcriptionEngine)
        _ollamaKey = State(initialValue: KeychainStore.get("ollama") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2).bold()

            Picker("Transcription engine", selection: $engine) {
                Text("SpeechAnalyzer (macOS 26, dual-channel)").tag("speechAnalyzer")
                Text("SpeechRecognizer (legacy)").tag("speechRecognizer")
            }
            Text(
                "SpeechAnalyzer transcribes both channels concurrently and downloads its model on first use; " +
                "SpeechRecognizer is the fallback. Changing this takes effect when you next press Listen."
            )
            .font(.caption).foregroundStyle(.secondary)

            Divider()

            SecureField("Ollama API key", text: $ollamaKey)
                .textFieldStyle(.roundedBorder)
            Text(
                "Optional — paste your Ollama Cloud key (ollama.com) to use cloud models like " +
                "deepseek-v4-flash. Leave blank to use your local Ollama at localhost:11434. " +
                "Stored in your macOS Keychain."
            )
            .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        ProviderSettings.transcriptionEngine = engine
        KeychainStore.set(ollamaKey.isEmpty ? nil : ollamaKey, for: "ollama")
        dismiss()
    }
}
