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
            Menu {
                if ai.appleUnavailableReason == nil {
                    providerChoice("Apple Intelligence · on-device", route: .apple)
                }
                providerChoice(ai.usesCustomEndpoint ? "Ollama · your server" : "Ollama Cloud", route: .ollama)
                Section("Cloud AI · sends your transcript to the service") {
                    ForEach(CloudAIPreset.all) { preset in
                        providerChoice(preset.name, route: .cloud(preset.id))
                    }
                }
                providerChoice(ai.openAI.isConfigured ? ai.openAI.providerLabel : "Custom server (OpenAI-compatible)",
                               route: .openAI)
            } label: {
                HStack {
                    Text("Summary provider").foregroundStyle(.primary)
                    Spacer()
                    Text(providerTitle).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Summary provider, \(providerTitle)")
            .accessibilityIdentifier("summaryProvider")
            .disabled(ai.testing || ai.refreshing)
            if let reason = ai.appleUnavailableReason {
                Text("\(reason) Choose a supported provider below and configure its server, model and credentials. "
                     + "Cloud and custom providers send text only when you choose and configure them. "
                     + "Microphone recording uses a separate on-device speech engine and does not require summary AI.")
                    .font(.caption).accessibilityIdentifier("appleIntelligenceUnavailable")
            }
            if ai.provider == .cloud {
                MobileCloudAISettingsRows(ai: ai)
                if ai.correctTranscript {
                    Text("Speech correction still uses the Ollama connection below.").font(.caption)
                }
            }
            if ai.provider == .openAI {
                MobileOpenAISettingsRows(ai: ai)
                if ai.correctTranscript {
                    Text("Speech correction still uses the Ollama connection below.").font(.caption)
                }
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
                Text("Point this at an Ollama server you run — use your computer's name, for example "
                     + "http://your-mac.local:11434 on the same Wi-Fi network. Plain http is allowed only for "
                     + ".local, localhost, loopback or link-local addresses. Use https for other addresses. "
                     + "No API key is needed for your own server, and your saved Ollama Cloud key is "
                     + "never sent there. The app never switches servers on its own.").font(.caption)
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from API") {
                    editingKey = false
                    operation = Task { await ai.refresh() }
                }.disabled(ai.refreshing || ai.testing)
                if ai.provider != .openAI && ai.provider != .cloud { summaryModelRows }
                if ai.provider != .openAI && ai.provider != .cloud, let status = ai.status {
                    Text(status).font(.callout).accessibilityIdentifier("ollamaStatus")
                }
            }
        }
        .onAppear { ai.refreshAppleAvailability() }
        .onDisappear { operation?.cancel(); key = ""; server = "" }
        if includeSpeechCorrection { MobileSpeechCorrectionSettings(ai: ai) }
    }

    private var providerTitle: String {
        switch ai.provider {
        case .apple: return ai.appleUnavailableReason == nil ? "Apple Intelligence · on-device" : "Apple Intelligence · unavailable"
        case .ollama: return ai.usesCustomEndpoint ? "Ollama · your server" : "Ollama Cloud"
        case .openAI: return ai.openAI.isConfigured ? ai.openAI.providerLabel : "Custom server (OpenAI-compatible)"
        case .cloud: return ai.cloud.providerLabel
        }
    }

    private func providerChoice(_ title: String, route: MobileAISettings.SummaryRoute) -> some View {
        Button(title) { ai.selectSummaryRoute(route) }
            .disabled(route == .apple && ai.appleUnavailableReason != nil)
    }

    /// Role models and the connection test for Ollama summaries. Hidden when summaries use an
    /// OpenAI-compatible server, which has its own rows; these then only configure speech correction.
    @ViewBuilder private var summaryModelRows: some View {
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
    }

    /// Names the exact destination so the recipient of a summary is never implicit.
    private var destinationExplanation: String {
        let endpoint: String = ai.endpointLabel
        let lead: String = ai.provider == .ollama
            ? "Summarize sends your notes and transcript to \(endpoint) using the selected model. "
            : "Speech correction uses \(endpoint). Your summaries " + (ai.provider == .apple
                ? "still use Apple Intelligence on-device. " : "go to \(ai.summaryEndpointLabel). ")
        let tail: String = ai.usesCustomEndpoint
            ? " That server is your own machine; nothing goes to ollama.com."
            : " Your Ollama account's usage limits apply."
        return lead + "Microphone audio stays on your device." + tail
    }
}
