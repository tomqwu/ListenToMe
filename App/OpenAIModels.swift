import Foundation
import ListenToMeCore

/// Queries an OpenAI-compatible endpoint for its available models (`GET {baseURL}/models`).
/// `baseURL` is the OpenAI base *including* `/v1`. Lists all returned model ids — the `/v1/models`
/// shape exposes no chat-capability flag, so (unlike `OllamaModels`) there is no capability probe.
enum OpenAIModels {
    static func installed(baseURL: URL, apiKey: String?) async -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.timeoutInterval = 5
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return OpenAIModelParsing.ids(from: data)
    }
}
