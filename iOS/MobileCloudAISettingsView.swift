import SwiftUI
import ListenToMeCore

/// Settings rows for the selected cloud AI service (issue #214): who receives the transcript, the
/// vendor's key and privacy pages, the user's own API key, per-role models and a connection test.
struct MobileCloudAISettingsRows: View {
    @Bindable var ai: MobileAISettings
    @State private var key = ""
    /// The service selected while the key was typed; Save refuses to store it under another one.
    @State private var keyVendor: CloudAIPreset.ID?
    @State private var operation: Task<Void, Never>?
    @FocusState private var editing: Bool

    private var cloud: MobileCloudAISettings { ai.cloud }
    private var busy: Bool { ai.testing || ai.refreshing }

    var body: some View {
        if let preset = cloud.preset {
            Group {
                Text(preset.disclosure).font(.headline).accessibilityIdentifier("cloudAIDisclosure")
                Text(explanation(preset)).font(.caption).accessibilityIdentifier("cloudAIDestination")
                Link("\(preset.vendor) privacy policy", destination: preset.privacyPolicyURL)
                    .accessibilityIdentifier("cloudAIPrivacyPolicy")
                SecureField(cloud.hasKey ? "Replace saved API key" : "\(preset.vendor) API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editing).accessibilityIdentifier("cloudAIAPIKey").disabled(busy)
                    .onChange(of: key) { keyVendor = key.isEmpty ? nil : cloud.vendor }
                Link("Get a key from \(preset.vendor)", destination: preset.keyPageURL)
                    .accessibilityIdentifier("cloudAIKeyPage")
                Button("Save API key") {
                    if ai.saveCloudKey(key, typedFor: keyVendor) { key = ""; editing = false }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    .accessibilityIdentifier("saveCloudAIKey")
                if cloud.hasKey {
                    Text("API key saved in Keychain for \(OpenAICompatibleEndpoint.hostLabel(preset.baseURL)) only")
                        .accessibilityIdentifier("savedCloudAIKey")
                    Button("Remove API key", role: .destructive) { ai.saveCloudKey("") }.disabled(busy)
                }
                Text("ListenToMe has no keys of its own: you pay \(preset.vendor) for what you use. Each service "
                     + "keeps its own key, and a key is only ever sent to its own service.").font(.caption)
                Button(ai.refreshing ? "Refreshing models…" : "Refresh models from \(preset.vendor)") {
                    editing = false
                    operation = Task { await ai.refreshCloudModels() }
                }.disabled(!cloud.hasKey || busy).accessibilityIdentifier("refreshCloudAIModels")
                ForEach(MobileSummaryMode.allCases) { role in
                    NavigationLink {
                        MobileRoleModelView(ai: ai, role: role)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.title + " model")
                            Text(cloud.selectedModel(for: role).isEmpty ? "Choose model" : cloud.selectedModel(for: role))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("choose-model-\(role.rawValue)").disabled(ai.testing)
                }
                Text("Quick and Auto need the model to answer in the Quick Summary format. Open the Quick model "
                     + "and tap Test this model to check; if it fails, Auto pauses with an explanation.").font(.caption)
                Button(ai.testing ? "Testing connection…" : "Test connection") {
                    editing = false
                    operation = Task { await ai.testConnection(for: .summary) }
                }.disabled(cloud.availability(for: .summary) != nil || busy)
                    .accessibilityIdentifier("testCloudAIConnection")
                Text("Test connection sends only a short test prompt, not your conversation.").font(.caption)
                if ai.testing { Button("Cancel connection test") { operation?.cancel() } }
                if let status = ai.status {
                    Text(status).font(.callout).accessibilityIdentifier("ollamaStatus")
                }
            }
            .onDisappear { operation?.cancel(); key = "" }
            // A key typed for one service never carries over to the next (#218 review).
            .onChange(of: cloud.vendor) { key = ""; keyVendor = nil }
        }
    }

    private func explanation(_ preset: CloudAIPreset) -> String {
        var text = "Summary and Quick Summary send your notes and transcript to \(preset.vendor) at "
            + "\(OpenAICompatibleEndpoint.hostLabel(preset.baseURL)) using your API key and the model you choose. "
            + "Microphone audio stays on your device. \(preset.vendor)'s privacy policy and terms apply."
        if preset.transport == .anthropic {
            text += " If Claude declines a request, Anthropic may re-run it on another Claude model."
        }
        return text
    }
}

/// The model list for one role on a cloud AI service: the vendor's suggestions it actually lists,
/// then everything it lists. Nothing is selected until the user taps a model.
struct MobileCloudModelSections: View {
    @Bindable var ai: MobileAISettings
    let role: MobileSummaryMode

    var body: some View {
        if let preset = ai.cloud.preset {
            Section {
                Text("Models \(preset.vendor) lists for your key. \(preset.disclosure). "
                     + (role == .quick
                        ? "Quick and Auto need the model to answer in the Quick Summary format; Test this model checks that."
                        : "Your selection stays fixed until you change it."))
            }
            let suggested = preset.suggestions(in: ai.cloud.models)
            if !suggested.isEmpty {
                Section("Suggested") {
                    ForEach(suggested, id: \.self) { name in
                        row(name, note: name == preset.highlightedModel ? "Suggested default" : nil)
                    }
                }
            }
            Section("\(preset.vendor) models") {
                ForEach(ai.cloud.models, id: \.self) { name in row(name, note: nil) }
            }
        }
    }

    private func row(_ name: String, note: String?) -> some View {
        Button {
            ai.selectModel(name, for: role)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if ai.selectedModel(for: role) == name { Image(systemName: "checkmark").accessibilityLabel("Selected") }
            }
        }.accessibilityIdentifier("model-\(name)").disabled(ai.testing)
    }
}
