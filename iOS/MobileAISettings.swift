import Foundation
import Observation
import ListenToMeCore

@MainActor @Observable
final class MobileAISettings {
    enum Provider: String, CaseIterable { case apple, ollama }
    var provider: Provider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "mobileAIProvider") }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "mobileOllamaModel") }
    }
    var quickModel: String {
        didSet { UserDefaults.standard.set(quickModel, forKey: "mobileOllamaQuickModel") }
    }
    var deepModel: String {
        didSet { UserDefaults.standard.set(deepModel, forKey: "mobileOllamaDeepModel") }
    }
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

    init() {
        provider = Provider(rawValue: UserDefaults.standard.string(forKey: "mobileAIProvider") ?? "") ?? .apple
        let savedModel = UserDefaults.standard.string(forKey: "mobileOllamaModel") ?? ""
        model = savedModel
        quickModel = UserDefaults.standard.string(forKey: "mobileOllamaQuickModel") ?? savedModel
        deepModel = UserDefaults.standard.string(forKey: "mobileOllamaDeepModel") ?? savedModel
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
            status = hasKey ? "API key saved in this device's Keychain." : "API key removed."
            return true
        } catch { status = error.localizedDescription; return false }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let fetched = try await OllamaCloudCatalog().fetch(apiKey: MobileKeychain.read())
            guard !fetched.isEmpty else { throw RecordingError.message("Ollama returned an empty model catalog. Try again later.") }
            models = fetched
            resolveRoleModels()
            status = fetched.contains(where: { $0.name == model })
                ? "Fetched \(fetched.count) models from Ollama. Refresh does not verify your API key; use Test connection."
                : "Your selected model is no longer listed. Choose an available model before summarizing."
        } catch { status = "Could not refresh models: \(error.localizedDescription). Your selection is kept." }
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
        if !hasKey { return "Add your Ollama API key in Settings." }
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
        let key = try MobileKeychain.read()
        guard !key.isEmpty else { throw RecordingError.message("Add your Ollama API key in Settings.") }
        guard !model.isEmpty else { throw RecordingError.message("Choose an Ollama model in Settings.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 480
        return OllamaProvider(model: model, baseURL: OllamaCloudCatalog.baseURL, apiKey: key,
                              urlSession: URLSession(configuration: configuration))
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
            status = "Connection verified: \(selectedModel(for: mode)) returned a complete response."
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
        let code = (error as NSError).code
        if (error as NSError).domain == "Ollama", code == 401 || code == 403 {
            return "Ollama rejected authentication (HTTP \(code)). Check the saved API key and account access."
        }
        return error.localizedDescription
    }
}
