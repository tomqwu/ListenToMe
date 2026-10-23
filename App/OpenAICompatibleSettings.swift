import SwiftUI
import ListenToMeCore

/// macOS settings for an OpenAI-compatible server — LM Studio, vLLM, llama.cpp, OpenRouter or
/// Ollama's `/v1` API (issue #52). Selected by the explicit `AIProcessingMode.openAI`; never chosen
/// automatically, never called local, and its API key is bound to the server origin it was saved for.
extension ProviderSettings {
    static let openAIKeyAccount = "openai-compatible"

    /// The validated API base the user saved, or empty for none.
    static var openAIBaseURL: String {
        get { UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIBaseURL") }
    }

    /// `scheme://host:port` the saved key belongs to.
    private static var openAIKeyOrigin: String {
        get { UserDefaults.standard.string(forKey: "openAIKeyOrigin") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIKeyOrigin") }
    }

    /// The saved server, re-validated on every read so a hand-edited default is never trusted.
    static func openAIEndpoint() -> URL? {
        openAIBaseURL.isEmpty ? nil : try? OpenAICompatibleEndpoint.normalize(openAIBaseURL)
    }

    /// The key, only for the server it was saved for; any mismatch sends no credential.
    static func openAIKey() -> String? {
        guard let endpoint = openAIEndpoint(),
              openAIKeyOrigin == OpenAICompatibleEndpoint.origin(of: endpoint),
              let key = KeychainStore.get(openAIKeyAccount), !key.isEmpty else { return nil }
        return key
    }

    /// Why automatic reviews cannot run on the selected route, or nil when they can.
    static func automaticReviewUnavailableReason(quickModel: String) -> String? {
        switch aiMode {
        case .apple: return AppleIntelligenceProvider.automaticQuickUnavailableReason
        case .openAI:
            if openAIEndpoint() == nil { return "Set your OpenAI-compatible server URL in Settings." }
            return quickModel.isEmpty ? "Choose a Quick model in the status rail." : nil
        case .cloudAI:
            if let reason = cloudAIUnavailableReason { return reason }
            return quickModel.isEmpty ? "Choose a Quick model in the status rail." : nil
        default: return nil
        }
    }

    /// Footer and status text: names an OpenAI-compatible destination honestly.
    static var aiModeLabel: String {
        if aiMode == .cloudAI { return cloudAIModeLabel }
        guard aiMode == .openAI else { return aiMode.label }
        guard let endpoint = openAIEndpoint() else { return "OpenAI-compatible — no server set" }
        return "OpenAI-compatible — " + OpenAICompatibleEndpoint.destinationLabel(endpoint)
    }

    /// Writes a change validated by `OpenAICompatibleSettingsChange.plan`. The Keychain goes first:
    /// if storing the key fails, nothing at all is written and this returns false. A removal that
    /// fails still clears the recorded origin, so the old key can never be sent again.
    static func applyOpenAI(_ change: OpenAICompatibleSettingsChange) -> Bool {
        switch change.keyAction {
        case .keep: break
        case let .store(key, origin):
            guard KeychainStore.set(key, for: openAIKeyAccount) else { return false }
            openAIKeyOrigin = origin
        case .remove:
            KeychainStore.delete(openAIKeyAccount)
            openAIKeyOrigin = ""
        }
        openAIBaseURL = change.baseURL
        return true
    }

    /// Ephemeral, so nothing an OpenAI-compatible server returns lands in a shared cache or cookie jar.
    static let openAISession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 600
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// The provider for one pane on the OpenAI-compatible route. Without a server it fails with the
    /// reason instead of sending anything anywhere.
    static func openAIProvider(model: String) -> any LLMProvider {
        guard let endpoint = openAIEndpoint() else {
            return UnavailableProvider(reason: "Set your OpenAI-compatible server URL in Settings.")
        }
        guard !model.isEmpty else {
            return UnavailableProvider(reason: "Choose a model for this pane in the status rail. ListenToMe never "
                + "picks one from an OpenAI-compatible server's list for you.")
        }
        return OpenAICompatibleProvider(model: model, baseURL: endpoint, apiKey: openAIKey(), urlSession: openAISession)
    }
}

/// `/v1/models` discovery for the per-pane pickers. Nothing is verified local: the list says
/// nothing about where a model runs.
enum OpenAICompatibleModels {
    static func discover() async -> OllamaModels.Discovery {
        guard let endpoint = ProviderSettings.openAIEndpoint() else {
            return OllamaModels.Discovery(
                problem: "Set your OpenAI-compatible server URL in Settings, then Refresh models.")
        }
        do {
            let names = try await OpenAICompatibleCatalog(session: ProviderSettings.openAISession)
                .fetch(baseURL: endpoint, apiKey: ProviderSettings.openAIKey())
            return OllamaModels.Discovery(names: names, problem: names.isEmpty
                ? "\(OpenAICompatibleEndpoint.hostLabel(endpoint)) listed no models. "
                    + "Load a model on it, then Refresh models."
                : nil)
        } catch {
            return OllamaModels.Discovery(problem: "Could not list models from "
                + "\(OpenAICompatibleEndpoint.hostLabel(endpoint)): \(error.localizedDescription)")
        }
    }
}

/// Stands in for a provider that cannot run, so a pane shows why instead of contacting a default host.
struct UnavailableProvider: LLMProvider {
    let id = "unavailable"
    let reason: String
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: QuickSummaryError.message(reason)) }
    }
}

/// The OpenAI-compatible server fields in Settings, with a live, honest description of the address.
struct OpenAICompatibleSettingsSection: View {
    @Binding var baseURL: String
    @Binding var key: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("OpenAI-compatible server URL, e.g. http://localhost:1234/v1", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("API key for this server (optional)", text: $key)
                .textFieldStyle(.roundedBorder)
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var note: String {
        let rules = "Works with LM Studio, vLLM, llama.cpp, OpenRouter and Ollama's /v1 API. Plain http:// is "
            + "allowed only for this Mac or a .local name; anything else needs https://. Redirects are never followed. "
            + "The key is stored in your macOS Keychain, sent only to this server, and removed when you change servers."
        do {
            let url = try OpenAICompatibleEndpoint.normalize(baseURL)
            return "Sends meeting text and attached context to \(OpenAICompatibleEndpoint.destinationLabel(url)). "
                + OpenAICompatibleEndpoint.privacyNote(url) + " " + rules
        } catch OpenAICompatibleEndpoint.ValidationError.empty {
            return "Enter the server's base URL. Nothing is sent until you set one. " + rules
        } catch {
            return error.localizedDescription
        }
    }
}
