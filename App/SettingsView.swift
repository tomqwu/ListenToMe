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

    init() {
        _engine = State(initialValue: ProviderSettings.transcriptionEngine)
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
        dismiss()
    }
}
