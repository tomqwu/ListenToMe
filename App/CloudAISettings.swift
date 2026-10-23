import SwiftUI
import ListenToMeCore

/// macOS settings for the cloud AI presets (issue #214): OpenAI, Anthropic Claude, Google Gemini,
/// DeepSeek, OpenRouter, Groq, Mistral and xAI. Selected only by the explicit
/// `AIProcessingMode.cloudAI`; each vendor keeps its own Keychain key, bound to its own origin, and
/// pane models are only ever the user's picks from that vendor's list.
extension ProviderSettings {
    /// The chosen service, or nil until the user picks one.
    static var cloudVendor: CloudAIPreset.ID? {
        get { UserDefaults.standard.string(forKey: "cloudAIVendor").flatMap(CloudAIPreset.ID.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: "cloudAIVendor") }
    }

    static var cloudPreset: CloudAIPreset? { cloudVendor.map(CloudAIPreset.preset) }

    private static func keyOriginDefault(_ id: CloudAIPreset.ID) -> String { "cloudAIKeyOrigin_\(id.rawValue)" }

    /// A vendor's key, only for the origin it was saved for; any mismatch sends no credential.
    static func cloudAIKey(for id: CloudAIPreset.ID) -> String? {
        let preset = CloudAIPreset.preset(id)
        guard UserDefaults.standard.string(forKey: keyOriginDefault(id)) == preset.origin,
              let key = KeychainStore.get(preset.keychainAccount), !key.isEmpty else { return nil }
        return key
    }

    /// The pane model on the cloud route, per vendor; empty until the user picks one.
    static func cloudModelKey(_ role: CopilotRole) -> String {
        "cloudAIModel_\(cloudVendor?.rawValue ?? "none")_\(role.rawValue)"
    }

    /// Writes a change validated by `CloudAISettingsChange.plan`. Returns false, having written
    /// nothing, when the Keychain refuses the key.
    static func applyCloudAI(_ change: CloudAISettingsChange) -> Bool {
        switch change.keyAction {
        case .keep: break
        case let .store(key, account, origin):
            guard let vendor = change.vendor, KeychainStore.set(key, for: account) else { return false }
            UserDefaults.standard.set(origin, forKey: keyOriginDefault(vendor))
        case .remove(let account):
            KeychainStore.delete(account)
            if let vendor = change.vendor { UserDefaults.standard.removeObject(forKey: keyOriginDefault(vendor)) }
        }
        if let vendor = change.vendor { cloudVendor = vendor }
        return true
    }

    /// Why the cloud route cannot run yet, or nil.
    static var cloudAIUnavailableReason: String? {
        guard let preset = cloudPreset else { return "Choose a cloud AI service in Settings." }
        return cloudAIKey(for: preset.id) == nil ? "Add your \(preset.vendor) API key in Settings." : nil
    }

    static var cloudAIModeLabel: String {
        guard let preset = cloudPreset else { return "Cloud AI — no service chosen" }
        return "Cloud AI — \(preset.name) · \(preset.disclosure.lowercased())"
    }

    /// Ephemeral, so nothing a vendor returns lands in a shared cache or cookie jar.
    static let cloudAISession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 600
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// The provider for one pane on the cloud route. Without a service, key or model it fails with
    /// the reason instead of sending anything.
    static func cloudAIProvider(model: String) -> any LLMProvider {
        if let reason = cloudAIUnavailableReason { return UnavailableProvider(reason: reason) }
        guard let preset = cloudPreset, let key = cloudAIKey(for: preset.id) else {
            return UnavailableProvider(reason: "Choose a cloud AI service in Settings.")
        }
        guard !model.isEmpty else {
            return UnavailableProvider(reason: "Choose a \(preset.vendor) model for this pane in the status rail. "
                + "ListenToMe never picks one for you.")
        }
        return preset.provider(model: model, apiKey: key, urlSession: cloudAISession)
    }
}

/// The vendor's model list for the per-pane pickers.
enum CloudAIModels {
    static func discover() async -> OllamaModels.Discovery {
        if let reason = ProviderSettings.cloudAIUnavailableReason { return OllamaModels.Discovery(problem: reason) }
        guard let preset = ProviderSettings.cloudPreset, let key = ProviderSettings.cloudAIKey(for: preset.id) else {
            return OllamaModels.Discovery(problem: "Choose a cloud AI service in Settings.")
        }
        do {
            let names = try await CloudAICatalog(session: ProviderSettings.cloudAISession).fetch(preset, apiKey: key)
            return OllamaModels.Discovery(names: names, problem: names.isEmpty
                ? "\(preset.vendor) listed no models for this API key." : nil)
        } catch {
            return OllamaModels.Discovery(problem: "Could not list models from \(preset.vendor): \(error.localizedDescription)")
        }
    }
}

/// The cloud AI fields in Settings: the service, who receives the transcript, the vendor's key and
/// privacy pages, and the user's own API key. Check key lists the vendor's models with that key and
/// sends no transcript.
struct CloudAISettingsSection: View {
    @Binding var vendor: CloudAIPreset.ID?
    @Binding var key: String
    @State private var check: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Cloud AI service", selection: $vendor) {
                Text("Choose a service").tag(CloudAIPreset.ID?.none)
                ForEach(CloudAIPreset.all) { Text($0.name).tag(CloudAIPreset.ID?.some($0.id)) }
            }
            if let preset = vendor.map(CloudAIPreset.preset) {
                Text(preset.disclosure).font(.headline)
                Text(explanation(preset)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("Get a key from \(preset.vendor)", destination: preset.keyPageURL)
                    Link("\(preset.vendor) privacy policy", destination: preset.privacyPolicyURL)
                }.font(.caption)
                HStack {
                    SecureField("\(preset.vendor) API key", text: $key).textFieldStyle(.roundedBorder)
                    Button(checking ? "Checking…" : "Check key") { Task { await checkKey(preset) } }
                        .disabled(checking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let check { Text(check).font(.caption).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text("Nothing is sent until you choose a service and add your own API key. ListenToMe has no keys "
                     + "of its own.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: vendor) { check = nil }
    }

    private func explanation(_ preset: CloudAIPreset) -> String {
        var text = "Sends meeting text and attached context to \(preset.vendor) at "
            + "\(OpenAICompatibleEndpoint.hostLabel(preset.baseURL)) with your API key. The key is stored in your "
            + "macOS Keychain and sent only to \(preset.vendor); each service keeps its own key. Choose each pane's "
            + "model in the status rail; ListenToMe never picks one. \(preset.vendor)'s privacy policy applies."
        if preset.transport == .anthropic {
            text += " If Claude declines a request, Anthropic may re-run it on another Claude model."
        }
        return text
    }

    private func checkKey(_ preset: CloudAIPreset) async {
        checking = true
        defer { checking = false }
        do {
            let models = try await CloudAICatalog(session: ProviderSettings.cloudAISession)
                .fetch(preset, apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            guard vendor == preset.id else { return }
            let suggested = preset.suggestions(in: models)
            check = "\(preset.vendor) accepted the key and lists \(models.count) models."
                + (suggested.isEmpty ? "" : " Suggested: " + suggested.joined(separator: ", ") + ".")
                + " Save, then choose each pane's model in the status rail."
        } catch {
            guard vendor == preset.id else { return }
            check = "Key check failed: \(error.localizedDescription)"
        }
    }
}
