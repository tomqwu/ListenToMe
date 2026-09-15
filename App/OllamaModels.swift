import Foundation
import ListenToMeCore

/// Queries the Ollama server (local or cloud) for installed models and their capabilities.
enum OllamaModels {
    static func installed(baseURL: URL = URL(string: "http://localhost:11434")!,
                          apiKey: String? = nil) async -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 5
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// What `/api/show` says about one model: whether it can chat (capabilities include
    /// "completion") and whether its metadata verifies it as a downloaded local model.
    /// Locality is reported for every mode, so callers can hand the verified-local set to
    /// `ModelRanking.roleDefaults` instead of guessing from the name (issue #137).
    struct Capability {
        var chatCapable = false
        var verifiedLocal = false
    }

    static func capability(_ name: String,
                           baseURL: URL = URL(string: "http://localhost:11434")!,
                           apiKey: String? = nil, localOnly: Bool = false) async -> Capability {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/show"))
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let caps = obj["capabilities"] as? [String] else { return Capability() }
        let local = ModelPrivacy.isVerifiedLocal(data)
        return Capability(chatCapable: caps.contains("completion") && (!localOnly || local),
                          verifiedLocal: local)
    }

    /// The models a route offers, with the subset whose `/api/show` metadata verifies them as local.
    struct Discovery {
        var names: [String] = []
        var verifiedLocal: Set<String> = []
    }

    /// Installed models that can chat (capabilities include "completion").
    /// Probes capabilities concurrently for fast cloud responses.
    static func chatModels(baseURL: URL = URL(string: "http://localhost:11434")!,
                           apiKey: String? = nil, localOnly: Bool = false) async -> Discovery {
        let names = await installed(baseURL: baseURL, apiKey: apiKey)
        guard !names.isEmpty else { return Discovery() }

        // Probe each model concurrently, preserving input order.
        let capabilities: [Capability] = await withTaskGroup(of: (Int, Capability).self) { group in
            for (index, name) in names.enumerated() {
                group.addTask {
                    (index, await capability(name, baseURL: baseURL, apiKey: apiKey, localOnly: localOnly))
                }
            }
            var results = [(Int, Capability)]()
            for await pair in group { results.append(pair) }
            results.sort { $0.0 < $1.0 }
            return results.map(\.1)
        }

        let chat = zip(names, capabilities).filter { $0.1.chatCapable }
        return Discovery(names: chat.map(\.0),
                         verifiedLocal: Set(chat.filter { $0.1.verifiedLocal }.map(\.0)))
    }
}
