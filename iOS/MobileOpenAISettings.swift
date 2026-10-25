import Foundation
import Observation
import ListenToMeCore

/// Settings for an OpenAI-compatible summary server (LM Studio, vLLM, llama.cpp, OpenRouter,
/// Ollama's `/v1` API; issue #52). Kept apart from the Ollama settings so neither provider's model
/// choices, catalog or credential leak into the other.
///
/// Privacy rules:
/// - Nothing is ever set automatically: the server is whatever the user typed, and empty means none.
/// - The API key lives in the Keychain and is bound to the server origin it was saved for.
///   Changing the server removes it, so a key for one host is never sent to another.
/// - The UI never calls this server "on-device": loopback and LAN addresses are "your server",
///   everything else "may leave this device" (`OpenAICompatibleEndpoint.Reach`).
@MainActor @Observable
final class MobileOpenAISettings {
    private enum Keys {
        static let baseURL = "mobileOpenAIBaseURL"
        static let keyOrigin = "mobileOpenAIKeyOrigin"
        static let catalog = "mobileOpenAICatalog"
        static let summary = "mobileOpenAIModel"
        static let quick = "mobileOpenAIQuickModel"
        static let contextWindows = "mobileOpenAIContextWindows"
        static let contractFailures = "mobileOpenAIQuickContractFailures"
    }

    /// The validated API base, or empty when no server is set.
    private(set) var baseURL: String { didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL); changed?() } }
    private(set) var models: [String] {
        didSet { UserDefaults.standard.set(models, forKey: Keys.catalog) }
    }
    private(set) var model: String { didSet { UserDefaults.standard.set(model, forKey: Keys.summary); changed?() } }
    private(set) var quickModel: String {
        didSet { UserDefaults.standard.set(quickModel, forKey: Keys.quick); changed?() }
    }
    private(set) var contextWindows: [String: Int] {
        didSet { UserDefaults.standard.set(contextWindows, forKey: Keys.contextWindows); changed?() }
    }
    var contextWindow: OpenAIContextWindow? {
        contextWindows[baseURL].flatMap { OpenAIContextWindow(tokens: $0) }
    }
    func setContextTokens(_ tokens: Int) {
        guard isConfigured else { return }
        if let window = OpenAIContextWindow(tokens: tokens) { contextWindows[baseURL] = window.tokens }
        else if tokens == 0 { contextWindows.removeValue(forKey: baseURL) }
    }

    private(set) var hasKey = false
    /// Server and model pairs that failed the Auto JSON check, so Auto can pause with a reason.
    private(set) var contractLedger: OpenAICompatibleContractLedger {
        didSet { UserDefaults.standard.set(contractLedger.failures, forKey: Keys.contractFailures); changed?() }
    }
    /// Called after any change that affects which server or model a request uses.
    @ObservationIgnored var changed: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        contextWindows = defaults.dictionary(forKey: Keys.contextWindows) as? [String: Int] ?? [:]
        let saved = defaults.string(forKey: Keys.baseURL) ?? ""
        // Re-validate on load: a value from an older build or a hand-edited plist is not trusted.
        baseURL = (try? OpenAICompatibleEndpoint.normalize(saved).absoluteString) ?? ""
        models = defaults.stringArray(forKey: Keys.catalog) ?? []
        model = defaults.string(forKey: Keys.summary) ?? ""
        quickModel = defaults.string(forKey: Keys.quick) ?? ""
        contractLedger = OpenAICompatibleContractLedger(failures: defaults.stringArray(forKey: Keys.contractFailures) ?? [])
        hasKey = (try? currentKey()).map { !$0.isEmpty } ?? false
    }

    var endpoint: URL? { baseURL.isEmpty ? nil : URL(string: baseURL) }
    var isConfigured: Bool { endpoint != nil }

    /// Picker text: honest about where the address points, never "on-device".
    var providerLabel: String {
        guard let endpoint else { return "OpenAI-compatible server" }
        return OpenAICompatibleEndpoint.reach(of: endpoint).isUsersOwnServer
            ? "OpenAI-compatible · your server" : "OpenAI-compatible · may leave device"
    }

    /// Prose destination, e.g. "your server at studio.local:1234" or "openrouter.ai (may leave this device)".
    var destinationLabel: String {
        endpoint.map(OpenAICompatibleEndpoint.destinationLabel) ?? "no OpenAI-compatible server"
    }

    // MARK: Server and key

    /// Saves an explicit server. Returns the status text to show. A different origin removes the saved
    /// key and the previous server's model list, since neither belongs to the new host.
    @discardableResult
    func saveBaseURL(_ raw: String) -> (saved: Bool, message: String) {
        let url: URL
        do { url = try OpenAICompatibleEndpoint.normalize(raw) } catch {
            return (false, (error.localizedDescription) + " The previous server is kept.")
        }
        var message = "Server set to \(url.absoluteString). " + OpenAICompatibleEndpoint.privacyNote(url)
        let previous = endpoint.map(OpenAICompatibleEndpoint.origin)
        if previous != OpenAICompatibleEndpoint.origin(of: url) {
            if hasKey {
                do { try removeKey() } catch { return (false, error.localizedDescription) }
                message += " The saved API key was removed because it belongs to the previous server."
            }
            forgetModels()
        }
        baseURL = url.absoluteString
        return (true, message)
    }

    /// Removes the server, its key and its model list. Summaries then need another provider or server.
    @discardableResult
    func clearServer() -> String {
        try? removeKey()
        forgetModels()
        baseURL = ""
        return "OpenAI-compatible server removed. Nothing is sent until you set a server again."
    }

    /// Saves (or, when empty, removes) the key for the current server.
    func saveKey(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint else { throw RecordingError.message("Set the server URL before saving its API key.") }
        if trimmed.isEmpty { try removeKey(); return "API key removed." }
        try MobileKeychain.save(trimmed, account: MobileKeychain.openAIAccount)
        UserDefaults.standard.set(OpenAICompatibleEndpoint.origin(of: endpoint), forKey: Keys.keyOrigin)
        hasKey = true
        changed?()
        return "API key saved in this device's Keychain for \(OpenAICompatibleEndpoint.hostLabel(endpoint)) only."
    }

    private func removeKey() throws {
        try MobileKeychain.save("", account: MobileKeychain.openAIAccount)
        UserDefaults.standard.removeObject(forKey: Keys.keyOrigin)
        hasKey = false
        changed?()
    }

    /// The key, but only for the origin it was saved for; any mismatch sends no credential at all.
    func currentKey() throws -> String {
        guard let endpoint, UserDefaults.standard.string(forKey: Keys.keyOrigin)
                == OpenAICompatibleEndpoint.origin(of: endpoint) else {
            return ""
        }
        return try MobileKeychain.read(account: MobileKeychain.openAIAccount)
    }

    // MARK: Models

    /// Ephemeral, so a server's model list never lands in the shared cache or cookie jar.
    static let catalogSession = URLSession(configuration: .ephemeral)

    func selectedModel(for mode: MobileSummaryMode) -> String {
        switch mode {
        case .summary: return model
        case .quick: return quickModel
        }
    }

    func selectModel(_ value: String, for mode: MobileSummaryMode) {
        switch mode {
        case .summary: model = value
        case .quick: quickModel = value
        }
    }

    /// Fetches `/models` from the saved server and keeps role choices that are still listed. A server
    /// with exactly one model (a typical LM Studio or llama.cpp setup) fills empty roles with it;
    /// with several, the user chooses, since a hosted catalog's first entry is no recommendation.
    func refresh(session: URLSession = MobileOpenAISettings.catalogSession) async throws -> Int {
        guard let endpoint else { throw RecordingError.message("Set the server URL first.") }
        let key = try currentKey()
        let fetched = try await OpenAICompatibleCatalog(session: session).fetch(baseURL: endpoint, apiKey: key)
        guard self.endpoint == endpoint else { throw CancellationError() }
        guard !fetched.isEmpty else {
            throw RecordingError.message("The server listed no models. Load a model on it, then refresh.")
        }
        models = fetched
        if fetched.count == 1, let only = fetched.first {
            for mode in MobileSummaryMode.allCases where selectedModel(for: mode).isEmpty {
                selectModel(only, for: mode)
            }
        }
        return fetched.count
    }

    private func forgetModels() {
        models = []
        model = ""; quickModel = ""
        contractLedger = OpenAICompatibleContractLedger()
    }

    // MARK: Availability and transport

    func availability(for mode: MobileSummaryMode) -> String? {
        guard isConfigured else { return "Set your OpenAI-compatible server URL in Settings." }
        let selected = selectedModel(for: mode)
        if selected.isEmpty { return "Refresh models and choose a \(mode.title) model in Settings." }
        if !models.isEmpty && !models.contains(selected) {
            return "The selected model is no longer listed by the server. Choose another model in Settings."
        }
        return nil
    }

    /// Why Auto is paused even though the server and model are set: the Quick model already failed
    /// the evaluator's JSON contract. Auto never retries a known-bad model silently.
    var automaticQuickReason: String? {
        guard let endpoint, contractLedger.hasFailed(endpoint, model: quickModel) else { return nil }
        return "\(quickModel) did not follow the Quick Summary format. "
            + "Choose another Quick model or test it again in Settings."
    }

    /// Records the result for the model that was actually tested, not whichever is selected now.
    func recordContract(model: String, passed: Bool) {
        guard let endpoint else { return }
        contractLedger.record(endpoint, model: model, passed: passed)
    }

    func client(for mode: MobileSummaryMode, transports: MobileTransports) throws -> OpenAICompatibleProvider {
        if let reason = availability(for: mode) { throw RecordingError.message(reason) }
        guard let endpoint else { throw RecordingError.message("Set your OpenAI-compatible server URL in Settings.") }
        let key = try currentKey()
        let session = transports.session(for: MobileTransports.summary,
                                         identity: "openai\u{1}" + MobileAISettings.transportIdentity(endpoint, key))
        return OpenAICompatibleProvider(
            model: selectedModel(for: mode), baseURL: endpoint, apiKey: key, urlSession: session,
            options: mode == .quick ? .init(temperature: 0, maximumTokens: 3_072) : .init(),
            contextWindow: contextWindow)
    }
}
