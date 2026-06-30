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
    /// Language the AI panes must reply in, independent of the spoken/transcription language.
    /// Empty id = "Auto" (the model matches the conversation). Stored as an id; mapped to a prompt
    /// directive via `responseLanguageOptions`.
    static var responseLanguageID: String {
        get { UserDefaults.standard.string(forKey: "responseLanguage") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "responseLanguage") }
    }
    /// (id, menu label, prompt directive). A nil directive means no language constraint.
    static let responseLanguageOptions: [(id: String, label: String, directive: String?)] = [
        ("", "Auto (match speaker)", nil),
        ("en", "English", "English"),
        ("zh-Hans", "\u{4e2d}\u{6587} (\u{7b80}\u{4f53})", "Simplified Chinese"),
        ("zh-Hant", "\u{4e2d}\u{6587} (\u{7e41}\u{9ad4})", "Traditional Chinese"),
        ("ja", "\u{65e5}\u{672c}\u{8a9e}", "Japanese"),
        ("ko", "\u{d55c}\u{ad6d}\u{c5b4}", "Korean"),
        ("es", "Espa\u{00f1}ol", "Spanish"),
        ("fr", "Fran\u{00e7}ais", "French"),
        ("de", "Deutsch", "German")
    ]
    /// The prompt directive for the current response-language selection, or nil for Auto.
    static func responseLanguageDirective() -> String? {
        responseLanguageOptions.first { $0.id == responseLanguageID }?.directive ?? nil
    }

    /// Max characters of attached file/folder content fed into prompts. Defaults to 16,000.
    static var referenceBudget: Int {
        get { let v = UserDefaults.standard.integer(forKey: "referenceBudget"); return v > 0 ? v : 16_000 }
        set { UserDefaults.standard.set(newValue, forKey: "referenceBudget") }
    }

    /// App appearance: "system" / "light" / "dark". Defaults to "system" (follows the OS appearance).
    static var appearance: String {
        get { UserDefaults.standard.string(forKey: "appearance") ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: "appearance") }
    }

    /// The SwiftUI color scheme for the current `appearance` setting; nil = follow the system.
    static func preferredColorScheme() -> ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// Selected use-case preset id; empty = none.
    static var presetID: String {
        get { UserDefaults.standard.string(forKey: "presetID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "presetID") }
    }

    /// Whether the experimental on-device speaker breakdown of the "Others" channel is available.
    /// Default `false` — it downloads CoreML models on first use and quality is user-validated.
    static var speakerDiarizationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "speakerDiarizationEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "speakerDiarizationEnabled") }
    }

    /// Whether finished sessions are persisted locally for cross-meeting search. Default `true`.
    static var saveSessionsForSearch: Bool {
        get { UserDefaults.standard.object(forKey: "saveSessionsForSearch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveSessionsForSearch") }
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
    @State private var responseLanguageID: String
    @State private var referenceBudget: Int
    @State private var saveSessions: Bool
    @State private var appearance: String
    @State private var speakerDiarization: Bool

    init() {
        _engine = State(initialValue: ProviderSettings.transcriptionEngine)
        _ollamaKey = State(initialValue: KeychainStore.get("ollama") ?? "")
        _responseLanguageID = State(initialValue: ProviderSettings.responseLanguageID)
        _referenceBudget = State(initialValue: ProviderSettings.referenceBudget)
        _saveSessions = State(initialValue: ProviderSettings.saveSessionsForSearch)
        _appearance = State(initialValue: ProviderSettings.appearance)
        _speakerDiarization = State(initialValue: ProviderSettings.speakerDiarizationEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2).bold()

            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            Text("ListenToMe follows the system appearance by default. Choose Light or Dark to override.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Toggle("Speaker diarization (experimental)", isOn: $speakerDiarization)
            Text(
                "Adds a \u{201C}Speakers\u{201D} action that groups the system-audio " +
                "(\u{201C}Others\u{201D}) channel into distinct voices and shows each one's talk-time " +
                "share. On-device; downloads a CoreML model on first use. Experimental \u{2014} " +
                "accuracy varies and is yours to validate."
            )
            .font(.caption).foregroundStyle(.secondary)

            Divider()

            Picker("Transcription engine", selection: $engine) {
                Text("SpeechAnalyzer (macOS 26, dual-channel)").tag("speechAnalyzer")
                Text("SpeechRecognizer (legacy)").tag("speechRecognizer")
                Text("WhisperKit (multilingual, downloads model)").tag("whisperKit")
            }
            Text(
                "SpeechAnalyzer transcribes both channels concurrently and downloads its model on first use; " +
                "SpeechRecognizer is the fallback. WhisperKit adds multilingual / code-switching transcription " +
                "and downloads a model on first use (segment-final only, no live partials). " +
                "Changing this takes effect when you next press Listen."
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

            Divider()

            Picker("Response language", selection: $responseLanguageID) {
                ForEach(ProviderSettings.responseLanguageOptions, id: \.id) {
                    Text($0.label).tag($0.id)
                }
            }
            Text(
                "Forces the AI panes (Listener, Quick, Deep) to reply in this language, whatever " +
                "language is spoken. \u{201C}Auto\u{201D} lets the model match the conversation. " +
                "Applies to your next response."
            )
            .font(.caption).foregroundStyle(.secondary)

            Divider()
            Picker("Reference file budget", selection: $referenceBudget) {
                Text("8K characters").tag(8_000)
                Text("16K characters").tag(16_000)
                Text("32K characters").tag(32_000)
                Text("64K characters").tag(64_000)
            }
            Text(
                "Maximum characters of attached file/folder content sent to the AI panes. " +
                "Larger uses more of the model's context."
            )
            .font(.caption).foregroundStyle(.secondary)

            Divider()
            Toggle("Save sessions locally for search", isOn: $saveSessions)
            Text(
                "Stored only on this Mac; used for cross-meeting search. Turn off to keep nothing."
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
        ProviderSettings.responseLanguageID = responseLanguageID
        ProviderSettings.referenceBudget = referenceBudget
        ProviderSettings.saveSessionsForSearch = saveSessions
        ProviderSettings.appearance = appearance
        ProviderSettings.speakerDiarizationEnabled = speakerDiarization
        // Honor the "Turn off to keep nothing" promise: wipe stored history whenever the toggle is
        // off. The store is file-backed, so a fresh instance's clear() deletes the JSON.
        if !saveSessions { SessionStore().clear() }
        KeychainStore.set(ollamaKey.isEmpty ? nil : ollamaKey, for: "ollama")
        dismiss()
    }
}
