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
    static var automaticReviewUnavailableReason: String? {
        switch aiMode {
        case .apple: return AppleIntelligenceProvider.automaticQuickUnavailableReason
        case .openAI: return openAIEndpoint() == nil ? "Set your OpenAI-compatible server URL in Settings." : nil
        default: return nil
        }
    }

    /// Footer and status text: names an OpenAI-compatible destination honestly.
    static var aiModeLabel: String {
        guard aiMode == .openAI else { return aiMode.label }
        guard let endpoint = openAIEndpoint() else { return "OpenAI-compatible — no server set" }
        return "OpenAI-compatible — " + OpenAICompatibleEndpoint.destinationLabel(endpoint)
    }

    /// Applies the Settings sheet's server and key together; throws without changing anything when
    /// the URL is invalid or the Keychain write fails. Moving to a different server origin removes
    /// the old key unless a new one was entered in the same save.
    static func saveOpenAI(baseURL raw: String, key: String, keyEdited: Bool) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.isEmpty ? nil : try OpenAICompatibleEndpoint.normalize(trimmed)
        let newOrigin = url.map(OpenAICompatibleEndpoint.origin)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyEdited {
            guard trimmedKey.isEmpty || newOrigin != nil else {
                throw QuickSummaryError.message("Set the OpenAI-compatible server URL before saving its API key.")
            }
            guard KeychainStore.set(trimmedKey.isEmpty ? nil : trimmedKey, for: openAIKeyAccount) else {
                throw QuickSummaryError.message("Could not save the API key in Keychain.")
            }
            openAIKeyOrigin = trimmedKey.isEmpty ? "" : (newOrigin ?? "")
        } else if newOrigin != openAIEndpoint().map(OpenAICompatibleEndpoint.origin) {
            KeychainStore.delete(openAIKeyAccount)
            openAIKeyOrigin = ""
        }
        openAIBaseURL = url?.absoluteString ?? ""
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
