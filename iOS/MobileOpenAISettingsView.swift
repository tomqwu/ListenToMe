import SwiftUI
import ListenToMeCore

/// Settings rows for an OpenAI-compatible summary server (issue #52): the server URL, an optional
/// API key bound to that server, the per-role models it lists and a connection test. Every line
/// names where summaries go; loopback and LAN addresses read "your server", anything else "may leave
/// this device", and nothing here is ever called on-device.
struct MobileOpenAISettingsRows: View {
    @Bindable var ai: MobileAISettings
    @State private var server = ""
    @State private var key = ""
    @State private var operation: Task<Void, Never>?
    @FocusState private var editing: Bool

    private var openAI: MobileOpenAISettings { ai.openAI }
    private var busy: Bool { ai.testing || ai.refreshing }

    var body: some View {
        Group {
            Text(explanation).accessibilityIdentifier("openAIDestination")
            Text("Server: \(openAI.isConfigured ? openAI.baseURL : "not set")").font(.caption)
                .accessibilityIdentifier("openAIServer")
            TextField("Server URL, e.g. http://your-mac.local:1234/v1", text: $server)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .focused($editing).accessibilityIdentifier("openAIBaseURL").disabled(busy)
            Button("Save server URL") {
                editing = false
                if ai.saveOpenAIBaseURL(server) { server = "" }
            }.disabled(server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                .accessibilityIdentifier("saveOpenAIBaseURL")
            if openAI.isConfigured {
                Button("Remove server", role: .destructive) { ai.clearOpenAIServer(); server = "" }.disabled(busy)
            }
            Text("Works with LM Studio, vLLM, llama.cpp, OpenRouter, Ollama's /v1 API and other "
                 + "/v1/chat/completions servers. Plain http:// is allowed only for this device or a .local name, "
                 + "such as http://your-mac.local:1234/v1; anything else needs https://. Redirects are never "
                 + "followed. The app never switches servers on its own.").font(.caption)
            Picker("Server context window", selection: Binding(
                get: { openAI.contextWindow?.tokens ?? 0 }, set: { openAI.setContextTokens($0) })) {
                Text("Unknown — server managed").tag(0)
                ForEach(OpenAIContextWindow.choices, id: \.self) { Text("\($0 / 1_024)K tokens").tag($0) }
            }.disabled(!openAI.isConfigured || busy).accessibilityIdentifier("openAIContextWindow")
            Text("Match the context size configured on this server, not the model's advertised maximum. "
                 + "This setting is saved per server URL. Space is reserved for the answer; oversized requests "
                 + "stop before sending. Unknown keeps the current server-managed behavior.").font(.caption)
            SecureField(openAI.hasKey ? "Replace saved API key" : "API key (optional)", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($editing).accessibilityIdentifier("openAIAPIKey").disabled(!openAI.isConfigured || busy)
            Button("Save API key") {
                if ai.saveOpenAIKey(key) { key = ""; editing = false }
            }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !openAI.isConfigured || busy)
            if openAI.hasKey {
                Text("API key saved in Keychain for this server only").accessibilityIdentifier("savedOpenAIKey")
                Button("Remove API key", role: .destructive) { ai.saveOpenAIKey("") }.disabled(busy)
            }
            Text("Local servers usually need no key. A saved key is sent only to this server and is removed "
                 + "when you change servers.").font(.caption)
            Button(ai.refreshing ? "Refreshing models…" : "Refresh models from server") {
                editing = false
                operation = Task { await ai.refreshSummaryModels() }
            }.disabled(!openAI.isConfigured || busy).accessibilityIdentifier("refreshOpenAIModels")
            ForEach(MobileSummaryMode.allCases) { role in
                NavigationLink {
                    MobileRoleModelView(ai: ai, role: role)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role.title + " model")
                        Text(openAI.selectedModel(for: role).isEmpty ? "Choose model" : openAI.selectedModel(for: role))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("choose-model-\(role.rawValue)").disabled(!openAI.isConfigured || ai.testing)
            }
            Text("Quick and Auto need the model to answer in the Quick Summary JSON format. Open the Quick model "
                 + "and tap Test this model to check; if it fails, Auto pauses with an explanation.").font(.caption)
            Button(ai.testing ? "Testing connection…" : "Test connection") {
                editing = false
                operation = Task { await ai.testConnection(for: .summary) }
            }.disabled(openAI.availability(for: .summary) != nil || busy)
                .accessibilityIdentifier("testOpenAIConnection")
            Text("Test connection sends only a short test prompt, not your conversation.").font(.caption)
            if ai.testing { Button("Cancel connection test") { operation?.cancel() } }
            if let status = ai.status {
                Text(status).font(.callout).accessibilityIdentifier("ollamaStatus")
            }
        }
        .onDisappear { operation?.cancel(); key = ""; server = "" }
    }

    /// Names the exact destination and how far it may reach, so the recipient is never implicit.
    private var explanation: String {
        guard let endpoint = openAI.endpoint else {
            return "Enter the address of an OpenAI-compatible server. Nothing is sent until you set one."
        }
        return "Summarize sends your notes and transcript to \(OpenAICompatibleEndpoint.destinationLabel(endpoint)) "
            + "using the selected model. Microphone audio stays on your device. "
            + OpenAICompatibleEndpoint.privacyNote(endpoint)
    }
}
