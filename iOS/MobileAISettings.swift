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
    var models: [OllamaCloudModel] = []
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
        hasKey = (try? MobileKeychain.read().isEmpty) == false
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
            let recent = OllamaCloudModel.recentVariants(in: fetched)
            if model.isEmpty {
                model = recent.first(where: { $0.family == "glm" && $0.name.contains("flash") })?.name
                    ?? recent.first?.name ?? fetched[0].name
            }
            if quickModel.isEmpty { quickModel = recent.first(where: { $0.name.contains("flash") })?.name ?? model }
            if deepModel.isEmpty {
                deepModel = recent.first(where: { $0.name.contains("pro") })?.name
                    ?? recent.first(where: { !$0.name.contains("flash") })?.name ?? model
            }
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

    func selectModel(_ value: String, for mode: MobileSummaryMode) {
        switch mode {
        case .summary: model = value
        case .quick: quickModel = value
        case .deep: deepModel = value
        }
    }

    var availability: String? { availability(for: .summary) }

    func availability(for mode: MobileSummaryMode) -> String? {
        let model = selectedModel(for: mode)
        if !hasKey { return "Add your Ollama API key in Settings." }
        if model.isEmpty { return "Refresh models and choose a model in Settings." }
        if !models.isEmpty && !models.contains(where: { $0.name == model }) {
            return "The selected model is no longer listed. Choose another model in Settings."
        }
        return nil
    }

    func client(for mode: MobileSummaryMode = .summary) throws -> OllamaProvider {
        let model = selectedModel(for: mode)
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
        if case OllamaStreamError.incomplete = error { return "Ollama's response ended before completion." }
        let code = (error as NSError).code
        if (error as NSError).domain == "Ollama", code == 401 || code == 403 {
            return "Ollama rejected authentication (HTTP \(code)). Check the saved API key and account access."
        }
        return error.localizedDescription
    }
}
