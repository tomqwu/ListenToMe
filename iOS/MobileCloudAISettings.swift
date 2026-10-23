import Foundation
import Observation
import ListenToMeCore

/// Settings for the cloud AI presets (issue #214): OpenAI, Anthropic Claude, Google Gemini, DeepSeek,
/// OpenRouter, Groq, Mistral and xAI. Kept apart from the Ollama and custom-server settings so no
/// provider's models, catalog or credential leak into another.
///
/// Privacy rules:
/// - Nothing is chosen for the user: no service until one is picked, no model until one is picked.
///   Suggested models are only highlighted.
/// - Each vendor has its own Keychain item, bound to that vendor's fixed origin. Switching vendors
///   keeps every vendor's key and model choices, and a key is only ever sent to its own vendor.
@MainActor @Observable
final class MobileCloudAISettings {
    private enum Keys {
        static let vendor = "mobileCloudAIVendor"
        static let contractFailures = "mobileCloudAIQuickContractFailures"
        static func catalog(_ id: CloudAIPreset.ID) -> String { "mobileCloudAI.\(id.rawValue).catalog" }
        static func keyOrigin(_ id: CloudAIPreset.ID) -> String { "mobileCloudAI.\(id.rawValue).keyOrigin" }
        static func model(_ id: CloudAIPreset.ID, _ mode: MobileSummaryMode) -> String {
            "mobileCloudAI.\(id.rawValue).\(mode.rawValue)Model"
        }
    }

    /// The chosen service, or nil until the user picks one.
    private(set) var vendor: CloudAIPreset.ID? {
        didSet { UserDefaults.standard.set(vendor?.rawValue, forKey: Keys.vendor); changed?() }
    }
    /// Model lists per vendor, as each vendor last reported them.
    private(set) var catalogs: [CloudAIPreset.ID: [String]] = [:]
    /// Role models per vendor; empty means not chosen.
    private(set) var choices: [CloudAIPreset.ID: [MobileSummaryMode: String]] = [:]
    /// Vendors with a key saved for their own origin.
    private(set) var keyedVendors: Set<CloudAIPreset.ID> = []
    /// Vendor and model pairs that failed the Auto JSON check, so Auto can pause with a reason.
    private(set) var contractLedger: OpenAICompatibleContractLedger {
        didSet { UserDefaults.standard.set(contractLedger.failures, forKey: Keys.contractFailures); changed?() }
    }
    /// Called after any change that affects which service, key or model a request uses.
    @ObservationIgnored var changed: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        vendor = defaults.string(forKey: Keys.vendor).flatMap(CloudAIPreset.ID.init(rawValue:))
        contractLedger = OpenAICompatibleContractLedger(failures: defaults.stringArray(forKey: Keys.contractFailures) ?? [])
        for id in CloudAIPreset.ID.allCases {
            catalogs[id] = defaults.stringArray(forKey: Keys.catalog(id)) ?? []
            var roles: [MobileSummaryMode: String] = [:]
            for mode in MobileSummaryMode.allCases { roles[mode] = defaults.string(forKey: Keys.model(id, mode)) ?? "" }
            choices[id] = roles
            if let key = try? currentKey(for: id), !key.isEmpty { keyedVendors.insert(id) }
        }
    }

    var preset: CloudAIPreset? { vendor.map(CloudAIPreset.preset) }
    var hasKey: Bool { vendor.map(keyedVendors.contains) ?? false }
    var models: [String] { vendor.flatMap { catalogs[$0] } ?? [] }

    /// Picker text, e.g. "Cloud AI · Anthropic Claude".
    var providerLabel: String { preset.map { "Cloud AI · \($0.name)" } ?? "Cloud AI" }

    /// Prose destination, e.g. "Anthropic (api.anthropic.com)".
    var destinationLabel: String {
        preset.map { "\($0.vendor) (\(OpenAICompatibleEndpoint.hostLabel($0.baseURL)))" } ?? "no cloud AI service"
    }

    /// Selects a service. Its own saved key and models come back with it; nothing is sent.
    func select(_ id: CloudAIPreset.ID) { if vendor != id { vendor = id } }

    // MARK: Keys

    /// Saves (or, when empty, removes) the key for the selected service only.
    func saveKey(_ value: String) throws -> String {
        guard let preset else { throw RecordingError.message("Choose a cloud AI service first.") }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try removeKey(for: preset.id)
            return "\(preset.vendor) API key removed."
        }
        try MobileKeychain.save(trimmed, account: preset.keychainAccount)
        UserDefaults.standard.set(preset.origin, forKey: Keys.keyOrigin(preset.id))
        keyedVendors.insert(preset.id)
        changed?()
        return "\(preset.vendor) API key saved in this device's Keychain. It is sent only to "
            + "\(OpenAICompatibleEndpoint.hostLabel(preset.baseURL))."
    }

    private func removeKey(for id: CloudAIPreset.ID) throws {
        try MobileKeychain.save("", account: CloudAIPreset.preset(id).keychainAccount)
        UserDefaults.standard.removeObject(forKey: Keys.keyOrigin(id))
        keyedVendors.remove(id)
        changed?()
    }

    /// A vendor's key, but only for the origin it was saved for; any mismatch sends no credential.
    func currentKey(for id: CloudAIPreset.ID) throws -> String {
        let preset = CloudAIPreset.preset(id)
        guard UserDefaults.standard.string(forKey: Keys.keyOrigin(id)) == preset.origin else { return "" }
        return try MobileKeychain.read(account: preset.keychainAccount)
    }

    // MARK: Models

    static let catalogSession = URLSession(configuration: .ephemeral)

    func selectedModel(for mode: MobileSummaryMode) -> String {
        vendor.flatMap { choices[$0]?[mode] } ?? ""
    }

    func selectModel(_ value: String, for mode: MobileSummaryMode) {
        guard let vendor else { return }
        choices[vendor, default: [:]][mode] = value
        UserDefaults.standard.set(value, forKey: Keys.model(vendor, mode))
        changed?()
    }

    /// Fetches the selected vendor's model list. Choices are kept; nothing is ever picked from the
    /// list, even when it holds a single model (#213 review).
    func refresh(session: URLSession = MobileCloudAISettings.catalogSession) async throws -> Int {
        guard let preset else { throw RecordingError.message("Choose a cloud AI service first.") }
        let key = try currentKey(for: preset.id)
        guard !key.isEmpty else { throw RecordingError.message("Add your \(preset.vendor) API key first.") }
        let fetched = try await CloudAICatalog(session: session).fetch(preset, apiKey: key)
        guard vendor == preset.id else { throw CancellationError() }
        guard !fetched.isEmpty else { throw RecordingError.message("\(preset.vendor) listed no models for this key.") }
        catalogs[preset.id] = fetched
        UserDefaults.standard.set(fetched, forKey: Keys.catalog(preset.id))
        return fetched.count
    }

    // MARK: Availability and transport

    func availability(for mode: MobileSummaryMode) -> String? {
        guard let preset else { return "Choose a cloud AI service in Settings." }
        guard hasKey else { return "Add your \(preset.vendor) API key in Settings." }
        let selected = selectedModel(for: mode)
        if selected.isEmpty { return "Refresh models and choose a \(mode.title) model in Settings." }
        if !models.isEmpty && !models.contains(selected) {
            return "\(preset.vendor) no longer lists the selected model. Choose another model in Settings."
        }
        return nil
    }

    /// Why Auto is paused although the service and model are set: the Quick model already failed the
    /// evaluator's JSON contract.
    var automaticQuickReason: String? {
        guard let preset, contractLedger.hasFailed(preset.baseURL, model: selectedModel(for: .quick)) else { return nil }
        return "\(selectedModel(for: .quick)) did not follow the Quick Summary format. "
            + "Choose another Quick model or test it again in Settings."
    }

    func recordContract(model: String, passed: Bool) {
        guard let preset else { return }
        contractLedger.record(preset.baseURL, model: model, passed: passed)
    }

    func client(for mode: MobileSummaryMode, transports: MobileTransports) throws -> any LLMProvider {
        if let reason = availability(for: mode) { throw RecordingError.message(reason) }
        guard let preset else { throw RecordingError.message("Choose a cloud AI service in Settings.") }
        let key = try currentKey(for: preset.id)
        let session = transports.session(for: MobileTransports.summary,
                                         identity: "cloud\u{1}" + MobileAISettings.transportIdentity(preset.baseURL, key))
        return preset.provider(model: selectedModel(for: mode), apiKey: key, urlSession: session,
                               options: mode == .quick ? .init(temperature: 0, maximumTokens: 3_072) : .init())
    }
}
