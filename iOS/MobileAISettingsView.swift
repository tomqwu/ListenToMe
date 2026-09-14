import SwiftUI
import ListenToMeCore

struct MobileAISettingsView: View {
    @Bindable var ai: MobileAISettings
    var includeSpeechCorrection = true
    @State private var key = ""
    @State private var server = ""
    @State private var operation: Task<Void, Never>?
    @FocusState private var editingKey: Bool

    var body: some View {
        Section("AI summaries") {
            Picker("Summary provider", selection: $ai.provider) {
                Text("Apple Intelligence · on-device").tag(MobileAISettings.Provider.apple)
                Text(ai.usesCustomEndpoint ? "Ollama · your server" : "Ollama Cloud")
                    .tag(MobileAISettings.Provider.ollama)
            }.accessibilityIdentifier("summaryProvider")
            if ai.provider == .apple, let reason = MobileAISettings.defaultProviderReason {
                Text("Apple Intelligence cannot run here, so new installs start on Ollama instead: \(reason)")
                    .font(.caption).accessibilityIdentifier("appleIntelligenceUnavailable")
            }
            if ai.provider == .ollama || ai.correctTranscript {
                Text(destinationExplanation)
                Text("Server: \(ai.endpointDescription)").font(.caption)
                    .accessibilityIdentifier("ollamaServer")
                SecureField(ai.hasKey ? "Replace saved API key" : "Ollama API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("ollamaAPIKey").focused($editingKey).disabled(ai.testing)
                Button("Save API key") {
                    if ai.saveKey(key) { key = ""; editingKey = false }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.testing)
                if ai.hasKey {
                    Text("API key saved in Keychain").accessibilityIdentifier("savedAPIKey")
                    Button("Remove API key", role: .destructive) { ai.saveKey("") }.disabled(ai.testing)
                }
                TextField("Ollama server URL (blank = https://ollama.com)", text: $server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).accessibilityIdentifier("ollamaBaseURL").disabled(ai.testing)
                Button("Save server URL") {
                    editingKey = false
                    if ai.saveBaseURL(server) { server = "" }
                }.disabled(ai.testing || ai.refreshing)
                if ai.usesCustomEndpoint {
                    Button("Use Ollama Cloud instead") { ai.saveBaseURL(""); server = "" }
                        .disabled(ai.testing || ai.refreshing)
                }
                Text("Point this at an Ollama server you run — for example http://your-mac.local:11434 on the same "
                     + "Wi-Fi network. The API key stays optional for your own server and is "
                     + "required for Ollama Cloud. "
                     + "The app never switches servers on its own.").font(.caption)
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from API") {
                    editingKey = false
                    operation = Task { await ai.refresh() }
                }.disabled(ai.refreshing || ai.testing)
                ForEach(MobileSummaryMode.allCases) { role in
                    NavigationLink {
                        MobileRoleModelView(ai: ai, role: role)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.title + " model")
                            Text(ai.selectedModel(for: role).isEmpty ? "Choose model" : ai.selectedModel(for: role))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("choose-model-\(role.rawValue)").disabled(ai.testing)
                }
                Text("Models run on the selected server; no model download to your phone is needed. " +
                     "The list comes from the API, including Flash and Pro variants when available.")
                    .font(.caption)
                Button(ai.testing ? "Testing connection…" : (key.isEmpty ? "Test connection" : "Save key and test connection")) {
                    editingKey = false
                    if !key.isEmpty {
                        guard ai.saveKey(key) else { return }
                        key = ""
                    }
                    operation = Task { await ai.testConnection(for: .summary) }
                }.disabled(ai.selectedModel(for: .summary).isEmpty
                           || (!ai.hasKey && key.isEmpty && !ai.usesCustomEndpoint)
                           || ai.testing || ai.refreshing)
                Text("Test connection sends only a short test prompt, not your conversation.").font(.caption)
                if ai.testing { Button("Cancel connection test") { operation?.cancel() } }
                if let status = ai.status {
                    Text(status).font(.callout).accessibilityIdentifier("ollamaStatus")
                }
            }
        }
        .onDisappear { operation?.cancel(); key = ""; server = "" }
        if includeSpeechCorrection { MobileSpeechCorrectionSettings(ai: ai) }
    }

    /// Names the exact destination so the recipient of a summary is never implicit.
    private var destinationExplanation: String {
        let endpoint: String = ai.endpointDescription
        let lead: String = ai.provider == .ollama
            ? "Summarize sends your notes and transcript to \(endpoint) using the selected model. "
            : "Speech correction uses \(endpoint). Your summaries still use Apple Intelligence on-device. "
        let tail: String = ai.usesCustomEndpoint
            ? " That server is your own machine; nothing goes to ollama.com."
            : " Your Ollama account's usage limits apply."
        return lead + "Microphone audio stays on your device." + tail
    }
}
