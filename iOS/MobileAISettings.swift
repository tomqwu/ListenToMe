import Foundation
import Observation
import ListenToMeCore

@MainActor @Observable
final class MobileAISettings {
    /// `openAI` is any OpenAI-compatible `/v1/chat/completions` server the user entered (issue #52);
    /// `cloud` is one of the cloud AI presets, such as OpenAI or Anthropic Claude (issue #214).
    enum Provider: String, CaseIterable { case apple, ollama, openAI = "openai", cloud }
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
    /// Long-lived request transports, shared with the speech-correction client.
    @ObservationIgnored let transports = MobileTransports()
    /// The OpenAI-compatible server, its key, catalog and per-role models (issue #52).
    let openAI = MobileOpenAISettings()
    /// The cloud AI presets: the chosen service, each vendor's key and per-role models (issue #214).
    let cloud = MobileCloudAISettings()
    @ObservationIgnored var quickSettingsChanged: (() -> Void)?
    @ObservationIgnored var correctionSettingsChanged: (() -> Void)?
    var models: [OllamaCloudModel] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(models) {
                UserDefaults.standard.set(data.base64EncodedString(), forKey: "mobileOllamaCatalog")
            }
        }
    }
    private(set) var appleUnavailableReason: String?
    @ObservationIgnored private let appleAvailability: () -> String?

    func refreshAppleAvailability() {
        let reason = appleAvailability()
        guard reason != appleUnavailableReason else { return }
        appleUnavailableReason = reason
        if provider == .apple { quickSettingsChanged?() }
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
        return appleUnavailableReason
    }

    init(appleAvailability: @escaping () -> String? = { AppleIntelligenceProvider.unavailableReason }) {
        self.appleAvailability = appleAvailability
        let reason = appleAvailability()
        appleUnavailableReason = reason
        // A previously saved choice always wins; only an absent/unknown value takes the default.
        let saved = Provider(rawValue: UserDefaults.standard.string(forKey: "mobileAIProvider") ?? "")
        provider = saved ?? Self.defaultProvider(unavailableReason: reason)
        hasSavedProviderChoice = saved != nil
        ollamaBaseURL = UserDefaults.standard.string(forKey: "mobileOllamaBaseURL") ?? ""
        let savedModel = UserDefaults.standard.string(forKey: "mobileOllamaModel") ?? ""
        model = savedModel
        quickModel = UserDefaults.standard.string(forKey: "mobileOllamaQuickModel") ?? savedModel
        // An older build's "mobileOllamaDeepModel" is left alone and never read: iOS has no Deep (#235).
        correctTranscript = UserDefaults.standard.bool(forKey: "mobileCorrectTranscript")
        correctionModel = UserDefaults.standard.string(forKey: "mobileCorrectionModel") ?? ""
        if let value = UserDefaults.standard.string(forKey: "mobileOllamaCatalog"),
           let data = Data(base64Encoded: value),
           let cached = try? JSONDecoder().decode([OllamaCloudModel].self, from: data) { models = cached }
        hasKey = (try? MobileKeychain.read().isEmpty) == false
        resolveRoleModels()
        openAI.changed = { [weak self] in self?.quickSettingsChanged?() }
        cloud.changed = { [weak self] in self?.quickSettingsChanged?() }
        if provider == .cloud && cloud.vendor == nil { provider = Self.defaultProvider(unavailableReason: reason) }   // no service left to use
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
        guard !trimmed.isEmpty, let parsed = URLComponents(string: trimmed),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty else { return nil }
        // URL.host() removes IPv6 brackets; URLComponents.host needs the literal host form.
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = parsed.port
        return components.url
    }

    static let cloudHost = OllamaCloudCatalog.baseURL.host()?.lowercased() ?? "ollama.com"

    /// Ollama Cloud is identified by host, so a hand-typed https://ollama.com is still the cloud.
    static func isCloud(_ url: URL) -> Bool { url.host()?.lowercased() == cloudHost }

    /// Apply the same explicit local-network HTTP rule as OpenAI-compatible servers.
    static func isBlockedPlainHTTPAddress(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http"
            && !OpenAICompatibleEndpoint.allowsPlainHTTP(host: url.host(percentEncoded: false) ?? "")
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
        guard !Self.isBlockedPlainHTTPAddress(url) else {
            status = "Use https:// for this address, or a .local name such as http://your-mac.local:11434. "
                + "Plain http is allowed only for .local, localhost, loopback or link-local addresses. "
                + "The previous server is kept."
            return false
        }
        let parsed = URLComponents(string: trimmed)
        let omitted = (parsed?.path.isEmpty == false && parsed?.path != "/")
            || parsed?.query != nil || parsed?.fragment != nil || parsed?.user != nil || parsed?.password != nil
        let normalizationNotice = omitted
            ? " Only the scheme, host and port are used; the path, query, fragment and credentials are not saved." : ""
        if Self.isCloud(url) {
            ollamaBaseURL = ""
            status = "Server set to Ollama Cloud (https://ollama.com)." + normalizationNotice
            return true
        }
        ollamaBaseURL = url.absoluteString
        status = "Server set to \(url.absoluteString). Requests use this server instead of ollama.com."
            + normalizationNotice
        return true
    }

    /// The saved credential is an Ollama Cloud key. It is never sent to a server the user entered,
    /// so a private endpoint cannot collect it.
    func apiKey(forEndpoint url: URL) throws -> String {
        Self.isCloud(url) ? try MobileKeychain.read() : ""
    }

    /// Whether opening a model list may contact the catalog without being asked. Nothing leaves the
    /// device on its own: an install on Apple Intelligence, or on Ollama Cloud with no key saved,
    /// waits for the explicit "Refresh models from API" button.
    var canRefreshAutomatically: Bool { provider == .ollama && (hasKey || usesCustomEndpoint) }

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
        if provider == .openAI { return openAI.selectedModel(for: mode) }
        if provider == .cloud { return cloud.selectedModel(for: mode) }
        switch mode {
        case .summary: return model
        case .quick: return quickModel
        }
    }

    static func isFlash(_ name: String) -> Bool { name.lowercased().contains("flash") }

    func models(for role: MobileSummaryMode) -> [OllamaCloudModel] {
        if provider == .openAI { return openAI.models.map { OllamaCloudModel(name: $0) } }
        if provider == .cloud { return cloud.models.map { OllamaCloudModel(name: $0) } }
        return models
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
    }

    func selectModel(_ value: String, for mode: MobileSummaryMode) {
        if provider == .openAI { openAI.selectModel(value, for: mode); return }
        if provider == .cloud { cloud.selectModel(value, for: mode); return }
        switch mode {
        case .summary: model = value
        case .quick: quickModel = value
        }
    }

    var availability: String? { availability(for: .summary) }

    func availability(for mode: MobileSummaryMode) -> String? {
        if provider == .apple { return appleUnavailableReason }
        if provider == .openAI { return openAI.availability(for: mode) }
        if provider == .cloud { return cloud.availability(for: mode) }
        let model = selectedModel(for: mode)
        if !hasKey && !usesCustomEndpoint { return "Add your Ollama API key in Settings." }
        if model.isEmpty { return "Refresh models and choose a model in Settings." }
        if !models.isEmpty && !models.contains(where: { $0.name == model }) {
            return "The selected model is no longer listed. Choose another model in Settings."
        }
        return nil
    }

    func client(for mode: MobileSummaryMode = .summary) throws -> any LLMProvider {
        if provider == .apple {
            refreshAppleAvailability()
            if let reason = appleUnavailableReason { throw RecordingError.message(reason) }
            return AppleIntelligenceProvider()
        }
        if provider == .openAI { return try openAI.client(for: mode, transports: transports) }
        if provider == .cloud { return try cloud.client(for: mode, transports: transports) }
        let model = selectedModel(for: mode)
        let endpoint = resolvedBaseURL
        let key = try apiKey(forEndpoint: endpoint)
        guard !key.isEmpty || usesCustomEndpoint else {
            throw RecordingError.message("Add your Ollama API key in Settings.")
        }
        guard !model.isEmpty else { throw RecordingError.message("Choose an Ollama model in Settings.") }
        return OllamaProvider(model: model, baseURL: endpoint, apiKey: key.isEmpty ? nil : key,
                              urlSession: transports.session(for: MobileTransports.summary,
                                                             identity: Self.transportIdentity(endpoint, key)),
                              options: mode == .quick ? .init(thinking: false, temperature: 0, maximumTokens: 3_072) : .init(),
                              manageContext: usesCustomEndpoint)
    }

    /// A transport may only be reused for the same destination and credential.
    static func transportIdentity(_ endpoint: URL, _ key: String) -> String {
        "\(endpoint.absoluteString)\u{1}\(key)"
    }

    func testConnection(for mode: MobileSummaryMode = .summary) async {
        guard !testing else { return }
        testing = true
        defer { testing = false }
        if provider == .openAI || provider == .cloud, mode == .quick { await testQuickContract(); return }
        // Name what was tested, not whatever is selected when the answer arrives (#218 review).
        let testedModel = selectedModel(for: mode)
        let testedDestination = summaryEndpointDescription
        do {
            var response = ""
            for try await delta in try client(for: mode).stream(LLMRequest(system: "Reply briefly.",
                messages: [ChatMessage(role: "user", content: "Reply with OK. This is a connection test.")])) {
                response += delta
                guard response.count < 10_000 else { throw RecordingError.message("Connection test response was too large.") }
            }
            status = "Connection verified: \(testedModel) at \(testedDestination) "
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
