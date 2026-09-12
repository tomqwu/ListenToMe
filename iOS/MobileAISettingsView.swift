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
                    .accessibilityIdentifier("ollamaAPIKey").focused($editingKey).disabled(ai.testing)
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
                ForEach(MobileSummaryMode.allCases) { role in
                    NavigationLink {
                        modelList(for: role)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.title + " model")
                            Text(ai.selectedModel(for: role).isEmpty ? "Choose model" : ai.selectedModel(for: role))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("choose-model-\(role.rawValue)").disabled(ai.testing)
                }
                Text("Cloud models run on Ollama; no model download to your phone is needed. " +
                     "The list comes from the API, including Flash and Pro variants when available.")
                    .font(.caption)
                Button(ai.testing ? "Testing connection…" : (key.isEmpty ? "Test connection" : "Save key and test connection")) {
                    editingKey = false
                    if !key.isEmpty {
                        guard ai.saveKey(key) else { return }
                        key = ""
                    }
                    operation = Task { await ai.testConnection(for: .summary) }
                }.disabled(ai.selectedModel(for: .summary).isEmpty || (!ai.hasKey && key.isEmpty) || ai.testing || ai.refreshing)
                Text("Test connection sends only a short test prompt, not your conversation.").font(.caption)
                if ai.testing { Button("Cancel connection test") { operation?.cancel() } }
                if let status = ai.status {
                    Text(status).font(.callout).accessibilityIdentifier("ollamaStatus")
                }
            }
        }
        .onDisappear { operation?.cancel(); key = "" }
    }

    private func modelList(for role: MobileSummaryMode) -> some View {
        List {
            Section {
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from API") {
                    operation = Task { await ai.refresh() }
                }.disabled(ai.refreshing || ai.testing)
                if let status = ai.status { Text(status).font(.caption).accessibilityIdentifier("ollamaStatus") }
                Button(ai.testing ? "Testing connection…" : "Test this model") {
                    operation = Task { await ai.testConnection(for: role) }
                }.disabled(ai.availability(for: role) != nil || ai.testing)
            }
            Section {
                Text("Newest API update per DeepSeek, GLM, Qwen and Kimi variant. " +
                     "Models absent from the API are not offered. Your selection stays fixed until you change it.")
            }
            Section("Recent family variants") {
                ForEach(OllamaCloudModel.recentVariants(in: ai.models)) { model in modelRow(model, for: role) }
            }
            Section("All API models") {
                ForEach(ai.models) { model in modelRow(model, for: role) }
            }
        }.navigationTitle("\(role.title) model")
            .task { if ai.models.isEmpty { await ai.refresh() } }
    }

    private func modelRow(_ model: OllamaCloudModel, for role: MobileSummaryMode) -> some View {
        Button {
            ai.selectModel(model.name, for: role)
        } label: {
            HStack {
                Text(model.name).foregroundStyle(.primary)
                Spacer()
                if ai.selectedModel(for: role) == model.name { Image(systemName: "checkmark").accessibilityLabel("Selected") }
            }
        }.accessibilityIdentifier("model-\(model.name)")
    }
}
