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
    /// BCP-47 locale id for transcription; empty means follow the system language ("Auto").
    static var transcriptionLocaleID: String {
        get { UserDefaults.standard.string(forKey: "transcriptionLocale") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "transcriptionLocale") }
    }
    /// Resolved transcription locale. An empty id follows the system language; Apple's on-device
    /// Speech does not auto-detect spoken language, so this selects the engine's primary language.
    /// Each transcriber further resolves this against *its* engine's supported locales (and falls
    /// back) so an unsupported choice can't leave a recording session silently producing nothing.
    static func transcriptionLocale() -> Locale {
        let id = transcriptionLocaleID
        return id.isEmpty ? Locale.current : Locale(identifier: id)
    }
    static func model(for role: CopilotRole) -> String {
        UserDefaults.standard.string(forKey: "model_\(role.rawValue)") ?? ollamaModel
    }
    static func setModel(_ model: String, for role: CopilotRole) {
        UserDefaults.standard.set(model, forKey: "model_\(role.rawValue)")
    }

    /// True once the user has explicitly chosen a model for this role in its pane dropdown.
    /// Unpinned roles follow the role-appropriate default and adapt as available models change.
    static func isPinned(_ role: CopilotRole) -> Bool {
        UserDefaults.standard.bool(forKey: "modelPinned_\(role.rawValue)")
    }
    static func pin(_ role: CopilotRole) {
        UserDefaults.standard.set(true, forKey: "modelPinned_\(role.rawValue)")
    }

    /// One-time migration for the pinning model. Pre-pinning builds persisted a model per role but
    /// couldn't tell an explicit pick from an auto-healed default. We preserve saved choices as
    /// explicit pins, except in the one case the old auto-heal produced: a model saved for *every*
    /// role with all values identical (panes collapsed onto one model). That collapse stays
    /// unpinned so the new role-aware defaults can apply. Runs once, guarded by a flag.
    static func migratePinningIfNeeded() {
        let flag = "modelPinningMigrated"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let saved = CopilotRole.allCases.map {
            (role: $0, model: UserDefaults.standard.string(forKey: "model_\($0.rawValue)"))
        }
        let present = saved.compactMap(\.model)
        // Collapse signature: a model saved for every role and all the same value.
        let collapsed = present.count == CopilotRole.allCases.count && Set(present).count == 1
        if !collapsed {
            for entry in saved where entry.model != nil { pin(entry.role) }
        }
        UserDefaults.standard.set(true, forKey: flag)
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
