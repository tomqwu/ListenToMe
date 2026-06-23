import Foundation

/// Queries the local Ollama server for installed models and their capabilities.
enum OllamaModels {
    static func installed(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 5
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// True if the model advertises chat/completion capability (not embedding-only).
    static func isChatCapable(_ name: String,
                              baseURL: URL = URL(string: "http://localhost:11434")!) async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/show"))
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let caps = obj["capabilities"] as? [String] else { return false }
        return caps.contains("completion")
    }

    /// Installed models that can chat (capabilities include "completion").
    static func chatModels(baseURL: URL = URL(string: "http://localhost:11434")!) async -> [String] {
        var result: [String] = []
        for name in await installed(baseURL: baseURL) where await isChatCapable(name, baseURL: baseURL) {
            result.append(name)
        }
        return result
    }

    /// Preferred default: a local (non-`:cloud`) chat model if any, else the first chat model.
    static func preferredChatModel(from chatModels: [String]) -> String? {
        chatModels.first { !$0.contains(":cloud") } ?? chatModels.first
    }
}
