import SwiftUI
import ListenToMeCore

struct MobileAISettingsView: View {
    @Bindable var ai: MobileAISettings
    @State private var key = ""
    @State private var operation: Task<Void, Never>?
    @FocusState private var editingKey: Bool

    var body: some View {
        Section("AI summaries") {
            Picker("Summary provider", selection: $ai.provider) {
                Text("Apple Intelligence · on-device").tag(MobileAISettings.Provider.apple)
                Text("Ollama Cloud").tag(MobileAISettings.Provider.ollama)
            }.accessibilityIdentifier("summaryProvider")
            if ai.provider == .ollama {
                Text("Summarize sends your notes and transcript to Ollama Cloud using the selected model. " +
                     "Microphone audio stays on your device. Your Ollama account's usage limits apply.")
                Text("Server: https://ollama.com").font(.caption)
                SecureField(ai.hasKey ? "Replace saved API key" : "Ollama API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("ollamaAPIKey").focused($editingKey)
                Button("Save API key") {
                    if ai.saveKey(key) { key = ""; editingKey = false }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.testing)
                if ai.hasKey {
                    Text("API key saved in Keychain").accessibilityIdentifier("savedAPIKey")
                    Button("Remove API key", role: .destructive) { ai.saveKey("") }.disabled(ai.testing)
                }
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from API") {
                    editingKey = false
                    operation = Task { await ai.refresh() }
                }.disabled(ai.refreshing || ai.testing)
                if !ai.model.isEmpty { Text("Selected: \(ai.model)").accessibilityIdentifier("selectedOllamaModel") }
                if !ai.models.isEmpty {
                    NavigationLink("Choose model") {
                        modelList
                    }.disabled(ai.testing)
                }
                Text("Cloud models run on Ollama; no model download to your phone is needed. " +
                     "The list comes from the API, including Flash and Pro variants when available.")
                    .font(.caption)
                Button(ai.testing ? "Testing connection…" : "Test connection") {
                    editingKey = false
                    operation = Task { await ai.testConnection() }
                }.disabled(ai.availability != nil || ai.testing || ai.refreshing)
                Text("Test connection sends only a short test prompt, not your conversation.").font(.caption)
                if ai.testing { Button("Cancel connection test") { operation?.cancel() } }
                if let status = ai.status {
                    Text(status).font(.callout).accessibilityIdentifier("ollamaStatus")
                }
            }
        }
        .onDisappear { operation?.cancel(); key = "" }
    }

    private var modelList: some View {
        List {
            Section {
                Text("Newest API update per DeepSeek, GLM, Qwen and Kimi variant. " +
                     "Models absent from the API are not offered. Your selection stays fixed until you change it.")
            }
            Section("Recent family variants") {
                ForEach(OllamaCloudModel.recentVariants(in: ai.models)) { model in modelRow(model) }
            }
            Section("All API models") {
                ForEach(ai.models) { model in modelRow(model) }
            }
        }.navigationTitle("Ollama models")
    }

    private func modelRow(_ model: OllamaCloudModel) -> some View {
        Button {
            ai.model = model.name
        } label: {
            HStack {
                Text(model.name).foregroundStyle(.primary)
                Spacer()
                if ai.model == model.name { Image(systemName: "checkmark").accessibilityLabel("Selected") }
            }
        }.accessibilityIdentifier("model-\(model.name)")
    }
}
