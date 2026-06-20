import SwiftUI
import ListenToMeCore

/// UserDefaults-backed provider/model selection. The API key lives in the Keychain, not here.
enum ProviderSettings {
    static var provider: String {
        get { UserDefaults.standard.string(forKey: "provider") ?? "ollama" }
        set { UserDefaults.standard.set(newValue, forKey: "provider") }
    }
    static var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.1" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }
    static var deepseekModel: String {
        get { UserDefaults.standard.string(forKey: "deepseekModel") ?? "deepseek-v4-flash" }
        set { UserDefaults.standard.set(newValue, forKey: "deepseekModel") }
    }
}

struct SettingsView: View {
    let router: ModelRouter
    @Environment(\.dismiss) private var dismiss

    @State private var provider: String
    @State private var ollamaModel: String
    @State private var deepseekModel: String
    @State private var deepseekKey: String
    @State private var validationError: String?

    init(router: ModelRouter) {
        self.router = router
        _provider = State(initialValue: ProviderSettings.provider)
        _ollamaModel = State(initialValue: ProviderSettings.ollamaModel)
        _deepseekModel = State(initialValue: ProviderSettings.deepseekModel)
        _deepseekKey = State(initialValue: KeychainStore.get("deepseek") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Settings").font(.title2).bold()

            Picker("Provider", selection: $provider) {
                Text("Ollama (local)").tag("ollama")
                Text("DeepSeek").tag("deepseek")
            }
            .pickerStyle(.segmented)

            if provider == "ollama" {
                TextField("Ollama model", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                Text("Requires a local Ollama server at http://localhost:11434.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("DeepSeek model", selection: $deepseekModel) {
                    Text("V4 Flash (fast, economical)").tag("deepseek-v4-flash")
                    Text("V4 Pro (flagship)").tag("deepseek-v4-pro")
                }
                SecureField("DeepSeek API key", text: $deepseekKey)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in your macOS Keychain; sent only to api.deepseek.com.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
    }

    private func save() -> Bool {
        if provider == "deepseek" {
            let key = deepseekKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                validationError = "Enter a DeepSeek API key, or switch to Ollama."
                return false
            }
            guard KeychainStore.set(key, for: "deepseek") else {
                validationError = "Couldn't save the key to your Keychain. Try again."
                return false
            }
            ProviderSettings.deepseekModel = deepseekModel
            ProviderSettings.provider = "deepseek"
            router.register(DeepSeekProvider(model: deepseekModel, apiKey: key))
            router.setActive("deepseek")
        } else {
            let model = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                validationError = "Enter an Ollama model name (e.g. llama3.1)."
                return false
            }
            ProviderSettings.ollamaModel = model
            ProviderSettings.provider = "ollama"
            router.register(OllamaProvider(model: model))
            router.setActive("ollama")
        }
        return true
    }
}
