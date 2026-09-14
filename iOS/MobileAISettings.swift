import Foundation
import Observation
import ListenToMeCore

@MainActor @Observable
final class MobileAISettings {
    enum Provider: String, CaseIterable { case apple, ollama }
    var provider: Provider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "mobileAIProvider")
            hasSavedProviderChoice = true
            quickSettingsChanged?()
        }
    }
    /// True once the user has picked a provider; until then the device default applies.
    private(set) var hasSavedProviderChoice = false
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "mobileOllamaModel"); quickSettingsChanged?() }
    }
    var quickModel: String {
        didSet { UserDefaults.standard.set(quickModel, forKey: "mobileOllamaQuickModel"); quickSettingsChanged?() }
    }
    var deepModel: String {
        didSet { UserDefaults.standard.set(deepModel, forKey: "mobileOllamaDeepModel"); quickSettingsChanged?() }
    }
    var correctTranscript: Bool {
        didSet {
            UserDefaults.standard.set(correctTranscript, forKey: "mobileCorrectTranscript")
            correctionSettingsChanged?()
        }
    }
    var correctionModel: String {
        didSet {
            UserDefaults.standard.set(correctionModel, forKey: "mobileCorrectionModel")
            correctionSettingsChanged?()
        }
    }
    /// User-supplied Ollama endpoint. Empty means Ollama Cloud; never set automatically.
    private(set) var ollamaBaseURL: String {
        didSet {
            UserDefaults.standard.set(ollamaBaseURL, forKey: "mobileOllamaBaseURL")
            quickSettingsChanged?(); correctionSettingsChanged?()
        }
    }
    @ObservationIgnored var quickSettingsChanged: (() -> Void)?
    @ObservationIgnored var correctionSettingsChanged: (() -> Void)?
    var models: [OllamaCloudModel] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(models) {
                UserDefaults.standard.set(data.base64EncodedString(), forKey: "mobileOllamaCatalog")
            }
        }
    }
    var status: String?
    var refreshing = false
    var testing = false
    var hasKey = false

    /// Fresh installs start on-device; Ollama is only the fallback when Apple Intelligence cannot run.
    /// Pure function of the availability string so both branches are directly testable.
    static func defaultProvider(unavailableReason: String?) -> Provider {
        unavailableReason == nil ? .apple : .ollama
    }
    static var defaultProvider: Provider { defaultProvider(unavailableReason: defaultProviderReason) }
    /// Why a fresh install would fall back to Ollama, or nil when the on-device default applies.
    static var defaultProviderReason: String? { AppleIntelligenceProvider.unavailableReason }

    /// Set only while this device is on the Ollama fallback because Apple Intelligence cannot run and
    /// the user has not chosen a provider. Never shown once the user picks one.
    var fallbackExplanation: String? {
        guard !hasSavedProviderChoice, provider == .ollama else { return nil }
        return Self.defaultProviderReason
    }

    init() {
        // A previously saved choice always wins; only an absent/unknown value takes the default.
        let saved = Provider(rawValue: UserDefaults.standard.string(forKey: "mobileAIProvider") ?? "")
        provider = saved ?? Self.defaultProvider
        hasSavedProviderChoice = saved != nil
        ollamaBaseURL = UserDefaults.standard.string(forKey: "mobileOllamaBaseURL") ?? ""
        let savedModel = UserDefaults.standard.string(forKey: "mobileOllamaModel") ?? ""
        model = savedModel
        quickModel = UserDefaults.standard.string(forKey: "mobileOllamaQuickModel") ?? savedModel
        deepModel = UserDefaults.standard.string(forKey: "mobileOllamaDeepModel") ?? savedModel
        correctTranscript = UserDefaults.standard.bool(forKey: "mobileCorrectTranscript")
        correctionModel = UserDefaults.standard.string(forKey: "mobileCorrectionModel") ?? ""
        if let value = UserDefaults.standard.string(forKey: "mobileOllamaCatalog"),
           let data = Data(base64Encoded: value),
           let cached = try? JSONDecoder().decode([OllamaCloudModel].self, from: data) { models = cached }
        hasKey = (try? MobileKeychain.read().isEmpty) == false
        resolveRoleModels()
    }

    @discardableResult
    func saveKey(_ value: String) -> Bool {
        do {
            try MobileKeychain.save(value.trimmingCharacters(in: .whitespacesAndNewlines))
            hasKey = !(try MobileKeychain.read()).isEmpty
            correctionSettingsChanged?(); quickSettingsChanged?()
            status = hasKey ? "API key saved in this device's Keychain." : "API key removed."
            return true
        } catch { status = error.localizedDescription; return false }
    }

    /// Accepts only an http(s) URL with a host; returns nil for anything else.
    static func normalizedBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }

    static let cloudHost = OllamaCloudCatalog.baseURL.host()?.lowercased() ?? "ollama.com"

    /// Ollama Cloud is identified by host, so a hand-typed https://ollama.com is still the cloud.
    static func isCloud(_ url: URL) -> Bool { url.host()?.lowercased() == cloudHost }

    /// App Transport Security only exempts plain http for .local, link-local and loopback names
    /// (NSAllowsLocalNetworking). A bare private IPv4 literal would pass validation and then fail
    /// opaquely at request time, so it is rejected with an explanation instead.
    static func isPlainHTTPPrivateAddress(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host()?.lowercased() else { return false }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }), let first = UInt8(parts[0]),
              let second = UInt8(parts[1]) else { return false }
        if first == 127 { return false }
        if first == 10 { return true }
        if first == 172, (16...31).contains(second) { return true }
        if first == 192, second == 168 { return true }
        if first == 169, second == 254 { return false }
        return false
    }

    var usesCustomEndpoint: Bool { !Self.isCloud(resolvedBaseURL) }
    var resolvedBaseURL: URL { Self.normalizedBaseURL(ollamaBaseURL) ?? OllamaCloudCatalog.baseURL }
    /// Destination shown in settings so the data's recipient is never implicit.
    var endpointDescription: String { resolvedBaseURL.absoluteString }
    /// Prose-friendly destination: the product name for the cloud, the exact URL for your own server.
    var endpointLabel: String { usesCustomEndpoint ? resolvedBaseURL.absoluteString : "Ollama Cloud" }

    /// Stores an explicit endpoint choice. Empty text — or the cloud host itself — restores Ollama Cloud.
    @discardableResult
    func saveBaseURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ollamaBaseURL = ""
            status = "Server set to Ollama Cloud (https://ollama.com)."
            return true
        }
        guard let url = Self.normalizedBaseURL(trimmed) else {
            status = "That server address is not a valid http:// or https:// URL. The previous server is kept."
            return false
        }
        guard !Self.isPlainHTTPPrivateAddress(url) else {
            status = "iOS blocks plain http to a numeric private address. Use your computer's "
                + "name instead, for example http://your-mac.local:11434. The previous server is kept."
            return false
        }
        if Self.isCloud(url) {
            ollamaBaseURL = ""
            status = "Server set to Ollama Cloud (https://ollama.com)."
            return true
        }
        ollamaBaseURL = url.absoluteString
        status = "Server set to \(url.absoluteString). Summaries go to that machine, not to ollama.com."
        return true
    }

    /// The saved credential is an Ollama Cloud key. It is never sent to a server the user entered,
    /// so a private endpoint cannot collect it.
    func apiKey(forEndpoint url: URL) throws -> String {
        Self.isCloud(url) ? try MobileKeychain.read() : ""
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let endpoint = resolvedBaseURL
            let fetched = try await OllamaCloudCatalog()
                .fetch(apiKey: try apiKey(forEndpoint: endpoint), baseURL: endpoint)
            guard !fetched.isEmpty else { throw RecordingError.message("Ollama returned an empty model catalog. Try again later.") }
            models = fetched
            resolveRoleModels()
            status = fetched.contains(where: { $0.name == model })
                ? "Fetched \(fetched.count) models from \(endpoint.absoluteString). "
                    + "Refresh does not verify your API key; use Test connection."
                : "Your selected model is no longer listed. Choose an available model before summarizing."
        } catch {
            status = "Could not refresh models from \(resolvedBaseURL.absoluteString): "
                + "\(Self.errorMessage(error)). Your selection is kept."
        }
    }

    func selectedModel(for mode: MobileSummaryMode) -> String {
        switch mode {
        case .summary: return model
        case .quick: return quickModel
        case .deep: return deepModel
        }
    }

    static func isFlash(_ name: String) -> Bool { name.lowercased().contains("flash") }

    func models(for role: MobileSummaryMode) -> [OllamaCloudModel] {
        role == .deep ? models.filter { !Self.isFlash($0.name) } : models
    }

    func resolveRoleModels() {
        let recent = OllamaCloudModel.recentVariants(in: models)
        let full = recent.filter { !Self.isFlash($0.name) }
        if correctionModel.isEmpty {
            correctionModel = recent.first(where: { $0.family == "glm" && Self.isFlash($0.name) })?.name
                ?? recent.first(where: { Self.isFlash($0.name) })?.name ?? ""
        }
        if model.isEmpty { model = full.first(where: { $0.family == "glm" })?.name ?? full.first?.name ?? "" }
        if quickModel.isEmpty {
            quickModel = recent.first(where: { $0.family == "glm" && Self.isFlash($0.name) })?.name
                ?? recent.first(where: { Self.isFlash($0.name) })?.name ?? model
        }
        if deepModel.isEmpty || Self.isFlash(deepModel) {
            let family = OllamaCloudModel(name: deepModel).family
            deepModel = full.first(where: { $0.family == family && $0.name.lowercased().contains("pro") })?.name
                ?? full.first(where: { $0.family == family })?.name
                ?? full.first(where: { $0.name.lowercased().contains("pro") })?.name ?? full.first?.name ?? ""
        }
    }

    func selectModel(_ value: String, for mode: MobileSummaryMode) {
        guard mode != .deep || !Self.isFlash(value) else {
            status = "Deep Summary needs a full model. Flash models are available for Quick Summary."
            return
        }
        switch mode {
        case .summary: model = value
        case .quick: quickModel = value
        case .deep: deepModel = value
        }
    }

    var availability: String? { availability(for: .summary) }

    func availability(for mode: MobileSummaryMode) -> String? {
        let model = selectedModel(for: mode)
        if mode == .deep && (model.isEmpty || Self.isFlash(model)) { return "Choose a full model for Deep Summary." }
        if !hasKey && !usesCustomEndpoint { return "Add your Ollama API key in Settings." }
        if model.isEmpty { return "Refresh models and choose a model in Settings." }
        if !models.isEmpty && !models.contains(where: { $0.name == model }) {
            return "The selected model is no longer listed. Choose another model in Settings."
        }
        return nil
    }

    func client(for mode: MobileSummaryMode = .summary) throws -> OllamaProvider {
        let model = selectedModel(for: mode)
        if mode == .deep && (model.isEmpty || Self.isFlash(model)) {
            throw RecordingError.message("Choose a full model for Deep Summary. Flash models cannot be used for this role.")
        }
        let endpoint = resolvedBaseURL
        let key = try apiKey(forEndpoint: endpoint)
        guard !key.isEmpty || usesCustomEndpoint else {
            throw RecordingError.message("Add your Ollama API key in Settings.")
        }
        guard !model.isEmpty else { throw RecordingError.message("Choose an Ollama model in Settings.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 480
        return OllamaProvider(model: model, baseURL: endpoint, apiKey: key.isEmpty ? nil : key,
                              urlSession: URLSession(configuration: configuration),
                              options: mode == .quick ? .init(thinking: false, temperature: 0, maximumTokens: 3_072) : .init())
    }

    func testConnection(for mode: MobileSummaryMode = .summary) async {
        guard !testing else { return }
        testing = true
        defer { testing = false }
        do {
            var response = ""
            for try await delta in try client(for: mode).stream(LLMRequest(system: "Reply briefly.",
                messages: [ChatMessage(role: "user", content: "Reply with OK. This is a connection test.")])) {
                response += delta
                guard response.count < 10_000 else { throw RecordingError.message("Connection test response was too large.") }
            }
            status = "Connection verified: \(selectedModel(for: mode)) at \(endpointDescription) "
                + "returned a complete response."
        } catch { status = "Connection test failed: \(Self.errorMessage(error))" }
    }

    static func errorMessage(_ error: Error) -> String {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return "Request cancelled." }
        if let network = error as? URLError {
            switch network.code {
            case .networkConnectionLost: return "The internet connection was lost."
            case .notConnectedToInternet: return "This device is offline. Connect to the internet to continue."
            case .timedOut: return "The request timed out. Try again when the connection improves."
            default: break
            }
        }
        if case OllamaStreamError.incomplete = error { return "Ollama's response ended before completion." }
        // On-device generation failures reach here only when something bypasses the provider; the
        // transport already maps them, and this keeps a raw "Exceeded context window size" off screen.
        if let apple = AppleIntelligenceProvider.message(for: error) { return apple }
        let code = (error as NSError).code
        if (error as NSError).domain == "Ollama", code == 401 || code == 403 {
            return "Ollama rejected authentication (HTTP \(code)). Check the saved API key and account access."
        }
        return error.localizedDescription
    }
}
