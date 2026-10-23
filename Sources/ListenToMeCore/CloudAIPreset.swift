import Foundation

/// One-tap cloud AI services (issue #214): a fixed address, the vendor's key and privacy pages, and
/// the request shape that vendor needs. The user picks a service, pastes their own API key and
/// picks models; the apps ship no keys and select none of these by default.
///
/// Privacy rules every preset keeps:
/// - Opt-in only, and labelled "Sends your transcript to <vendor>".
/// - One Keychain item per vendor (`keychainAccount`), sent only to that vendor's origin. The address
///   is fixed in code, so switching vendors can never send one vendor's key to another.
/// - Models come from the vendor's own list and are never auto-assigned; `suggestedModels` are only
///   highlighted when the vendor lists them.
/// - The custom server's transport guarantees (#52) apply unchanged: redirects refused, 16 MiB cap,
///   stream validation and key masking.
public struct CloudAIPreset: Sendable, Equatable, Identifiable {
    public enum ID: String, CaseIterable, Sendable, Codable {
        case openAI = "openai", anthropic, gemini, deepSeek = "deepseek", openRouter = "openrouter"
        case groq, mistral, xAI = "xai"
    }

    public enum Transport: Sendable, Equatable {
        case openAICompatible(OpenAICompatibleDialect)
        /// Anthropic's native Messages API (`AnthropicProvider`).
        case anthropic
    }

    public let id: ID
    /// Menu name, such as "Anthropic Claude".
    public let name: String
    /// Who receives the transcript, such as "Anthropic".
    public let vendor: String
    /// API base: `chat/completions` (or `messages`) and `models` hang off it.
    public let baseURL: URL
    public let transport: Transport
    public let keyPageURL: URL
    public let privacyPolicyURL: URL
    /// Highlighted in the model list when the vendor lists them; never selected automatically.
    public let suggestedModels: [String]
    /// The suggestion the picker marks first. Still the user's choice.
    public let highlightedModel: String?
    /// A prefix the vendor's model list adds that chat requests do not need (Gemini's `models/`).
    let modelIDPrefix: String?

    /// The Keychain item for this vendor's key; one per vendor, never shared.
    public var keychainAccount: String { "cloud-ai-" + id.rawValue }
    /// `scheme://host:port` the key is bound to.
    public var origin: String { OpenAICompatibleEndpoint.origin(of: baseURL) }
    /// The disclosure each preset carries wherever it can be chosen.
    public var disclosure: String { "Sends your transcript to \(vendor)" }
    public var chatURL: URL {
        transport == .anthropic ? baseURL.appendingPathComponent("messages") : OpenAICompatibleEndpoint.chatURL(baseURL)
    }
    public var modelsURL: URL { OpenAICompatibleEndpoint.modelsURL(baseURL) }

    /// Request headers for this vendor, including the credential. Only ever sent to `baseURL`.
    public func headers(apiKey: String) -> [String: String] {
        switch transport {
        case .anthropic:
            return ["x-api-key": apiKey, "anthropic-version": AnthropicProvider.apiVersion]
        case .openAICompatible(let dialect):
            return dialect.headers.merging(["Authorization": "Bearer \(apiKey)"]) { _, credential in credential }
        }
    }

    /// The provider for one model. `options` set the chat token cap for OpenAI-compatible vendors.
    public func provider(model: String, apiKey: String, urlSession: URLSession = .shared,
                         options: OpenAICompatibleProvider.Options = .init()) -> any LLMProvider {
        switch transport {
        case .anthropic:
            return AnthropicProvider(model: model, apiKey: apiKey, baseURL: baseURL, urlSession: urlSession)
        case .openAICompatible(let dialect):
            return OpenAICompatibleProvider(model: model, baseURL: baseURL, apiKey: apiKey, urlSession: urlSession,
                                            options: options, dialect: dialect)
        }
    }

    /// Model IDs as chat requests take them.
    func chatModelID(_ listed: String) -> String {
        guard let modelIDPrefix, listed.hasPrefix(modelIDPrefix) else { return listed }
        return String(listed.dropFirst(modelIDPrefix.count))
    }

    /// `suggestedModels` the vendor actually lists, highlighted model first.
    public func suggestions(in listed: [String]) -> [String] {
        let available = Set(listed)
        return suggestedModels.filter(available.contains)
    }

    public static func preset(_ id: ID) -> CloudAIPreset {
        guard let preset = all.first(where: { $0.id == id }) else { preconditionFailure("Unknown preset \(id)") }
        return preset
    }

    /// App attribution OpenRouter shows on its dashboards. Optional, and never a credential.
    public static let openRouterHeaders = ["HTTP-Referer": "https://github.com/tomqwu/ListenToMe", "X-Title": "ListenToMe"]

    // Base URLs and model endpoints checked against each vendor's documentation on 2026-10-23.
    public static let all: [CloudAIPreset] = [
        CloudAIPreset(
            id: .openAI, name: "OpenAI", vendor: "OpenAI", baseURL: url("https://api.openai.com/v1"),
            transport: .openAICompatible(.init(maximumTokensField: "max_completion_tokens", sendsTemperature: false,
                                               quickReasoning: .effort("none"))),
            keyPageURL: url("https://platform.openai.com/api-keys"),
            privacyPolicyURL: url("https://openai.com/policies/privacy-policy/"),
            suggestedModels: [], highlightedModel: nil, modelIDPrefix: nil),
        CloudAIPreset(
            id: .anthropic, name: "Anthropic Claude", vendor: "Anthropic", baseURL: AnthropicProvider.defaultBaseURL,
            transport: .anthropic,
            keyPageURL: url("https://platform.claude.com/settings/keys"),
            privacyPolicyURL: url("https://www.anthropic.com/legal/privacy"),
            suggestedModels: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"],
            highlightedModel: "claude-opus-5-5", modelIDPrefix: nil),
        CloudAIPreset(
            id: .gemini, name: "Google Gemini", vendor: "Google",
            baseURL: url("https://generativelanguage.googleapis.com/v1beta/openai"),
            transport: .openAICompatible(.init(quickReasoning: .effort("none"))),
            keyPageURL: url("https://aistudio.google.com/apikey"),
            privacyPolicyURL: url("https://ai.google.dev/gemini-api/terms"),
            suggestedModels: [], highlightedModel: nil, modelIDPrefix: "models/"),
        CloudAIPreset(
            id: .deepSeek, name: "DeepSeek", vendor: "DeepSeek", baseURL: url("https://api.deepseek.com"),
            transport: .openAICompatible(.init(quickReasoning: .thinkingDisabled)),
            keyPageURL: url("https://platform.deepseek.com/api_keys"),
            privacyPolicyURL: url("https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html"),
            suggestedModels: ["deepseek-flash", "deepseek-v4-pro"], highlightedModel: nil, modelIDPrefix: nil),
        CloudAIPreset(
            id: .openRouter, name: "OpenRouter", vendor: "OpenRouter", baseURL: url("https://openrouter.ai/api/v1"),
            transport: .openAICompatible(.init(quickReasoning: .openRouter, headers: openRouterHeaders)),
            keyPageURL: url("https://openrouter.ai/settings/keys"),
            privacyPolicyURL: url("https://openrouter.ai/privacy"),
            suggestedModels: [], highlightedModel: nil, modelIDPrefix: nil),
        CloudAIPreset(
            id: .groq, name: "Groq", vendor: "Groq", baseURL: url("https://api.groq.com/openai/v1"),
            transport: .openAICompatible(.init(quickReasoning: .effort("none"))),
            keyPageURL: url("https://console.groq.com/keys"),
            privacyPolicyURL: url("https://groq.com/privacy-policy/"),
            suggestedModels: [], highlightedModel: nil, modelIDPrefix: nil),
        CloudAIPreset(
            id: .mistral, name: "Mistral", vendor: "Mistral AI", baseURL: url("https://api.mistral.ai/v1"),
            transport: .openAICompatible(.init(quickReasoning: .none)),
            keyPageURL: url("https://console.mistral.ai/api-keys"),
            privacyPolicyURL: url("https://legal.mistral.ai/terms/privacy-policy/"),
            suggestedModels: [], highlightedModel: nil, modelIDPrefix: nil),
        CloudAIPreset(
            id: .xAI, name: "xAI Grok", vendor: "xAI", baseURL: url("https://api.x.ai/v1"),
            transport: .openAICompatible(.init(quickReasoning: .none)),
            keyPageURL: url("https://console.x.ai/"),
            privacyPolicyURL: url("https://x.ai/legal/privacy-policy"),
            suggestedModels: ["grok-4.7"], highlightedModel: nil, modelIDPrefix: nil)
    ]

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { preconditionFailure("Invalid preset URL \(string)") }
        return url
    }
}

/// Lists a preset's models (`GET <base>/models`) with that vendor's headers. Redirects are refused
/// and the key goes only to the preset's own address.
public struct CloudAICatalog: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(_ preset: CloudAIPreset, apiKey: String) async throws -> [String] {
        var url = preset.modelsURL
        if preset.transport == .anthropic {
            // One page holds every Claude model; the API caps a page at 1,000.
            url = url.appending(queryItems: [URLQueryItem(name: "limit", value: "1000")])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        for (name, value) in preset.headers(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (bytes, _) = try await preset.transport == .anthropic
                ? AnthropicTransport.open(request, session: session, apiKey: apiKey)
                : OpenAICompatibleTransport.open(request, session: session, apiKey: apiKey)
            let body = try await OpenAICompatibleTransport.collect(bytes, limit: OpenAICompatibleCatalog.maximumBytes,
                                                                 throwing: true)
            var seen = Set<String>()
            return try OpenAICompatibleCatalog.parse(body).map(preset.chatModelID).filter { seen.insert($0).inserted }
        } catch {
            throw OpenAICompatibleTransport.mapped(error, host: preset.baseURL, apiKey: apiKey)
        }
    }
}
