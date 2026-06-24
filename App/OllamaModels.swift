import Foundation

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

    /// True if the model advertises chat/completion capability (not embedding-only).
    static func isChatCapable(_ name: String,
                              baseURL: URL = URL(string: "http://localhost:11434")!,
                              apiKey: String? = nil) async -> Bool {
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
              let caps = obj["capabilities"] as? [String] else { return false }
        return caps.contains("completion")
    }

    /// Installed models that can chat (capabilities include "completion").
    /// Probes capabilities concurrently for fast cloud responses.
    static func chatModels(baseURL: URL = URL(string: "http://localhost:11434")!,
                           apiKey: String? = nil) async -> [String] {
        let names = await installed(baseURL: baseURL, apiKey: apiKey)
        guard !names.isEmpty else { return [] }

        // Probe each model concurrently, preserving input order.
        let capable: [Bool] = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, name) in names.enumerated() {
                group.addTask {
                    let ok = await isChatCapable(name, baseURL: baseURL, apiKey: apiKey)
                    return (index, ok)
                }
            }
            var results = [(Int, Bool)]()
            for await pair in group { results.append(pair) }
            results.sort { $0.0 < $1.0 }
            return results.map(\.1)
        }

        return zip(names, capable).compactMap { name, ok in ok ? name : nil }
    }

    /// Preferred default: a local (non-`:cloud`) chat model if any, else the first chat model.
    static func preferredChatModel(from chatModels: [String]) -> String? {
        chatModels.first { !$0.contains(":cloud") } ?? chatModels.first
    }
}
