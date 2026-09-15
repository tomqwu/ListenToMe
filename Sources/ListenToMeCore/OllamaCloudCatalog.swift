import Foundation

/// Model IDs always come from the live API, including dated tags and future variants.
public struct OllamaCloudModel: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let modifiedAt: String?
    public var id: String { name }
    enum CodingKeys: String, CodingKey { case name; case modifiedAt = "modified_at" }

    public init(name: String, modifiedAt: String? = nil) {
        self.name = name; self.modifiedAt = modifiedAt
    }

    public var family: String {
        let lower = name.lowercased()
        return ["deepseek", "glm", "qwen", "kimi"].first(where: { lower.hasPrefix($0) }) ?? "Other"
    }

    private var variant: String {
        let lower = name.lowercased()
        if lower.contains("flash") { return "flash" }
        if lower.contains("pro") { return "pro" }
        return "standard"
    }

    /// Newest API modification time per requested family/variant, not a claim about release dates.
    public static func recentVariants(in models: [Self]) -> [Self] {
        let families = ["deepseek", "glm", "qwen", "kimi"]
        return families.flatMap { family in
            ["standard", "pro", "flash"].compactMap { variant in
                models.filter { $0.family == family && $0.variant == variant }.sorted(by: newer).first
            }
        }
    }

    public static func newer(_ lhs: Self, _ rhs: Self) -> Bool {
        let formatter = ISO8601DateFormatter()
        func date(_ value: String?) -> Date {
            guard let value else { return .distantPast }
            if let parsed = formatter.date(from: value) { return parsed }
            formatter.formatOptions.insert(.withFractionalSeconds)
            let parsed = formatter.date(from: value) ?? .distantPast
            formatter.formatOptions.remove(.withFractionalSeconds)
            return parsed
        }
        let left = date(lhs.modifiedAt), right = date(rhs.modifiedAt)
        return left == right ? lhs.name.compare(rhs.name, options: .numeric) == .orderedDescending : left > right
    }
}

public enum OllamaCatalogError: LocalizedError, Equatable {
    case missingAPIKey
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Ollama API key to list Ollama Cloud models, or set your own server URL."
        }
    }
}

public struct OllamaCloudCatalog: Sendable {
    public static let baseURL = URL(string: "https://ollama.com")!
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    /// `baseURL` defaults to Ollama Cloud; pass a user-supplied server to list models it hosts.
    /// Listing the cloud catalog without a key would be an anonymous request to ollama.com the user
    /// never opted into, so it fails locally instead of being sent. A server the user entered has
    /// no such credential and is still listed.
    public func fetch(apiKey: String, baseURL: URL = OllamaCloudCatalog.baseURL) async throws -> [OllamaCloudModel] {
        if apiKey.isEmpty, baseURL.host()?.lowercased() == Self.baseURL.host()?.lowercased() {
            throw OllamaCatalogError.missingAPIKey
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Surface the server's own explanation (bad key, quota) rather than a bare status.
            throw OllamaStreamError.fromHTTP(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                             body: data)
        }
        struct Catalog: Decodable { let models: [OllamaCloudModel] }
        let models = try JSONDecoder().decode(Catalog.self, from: data).models
        var seen = Set<String>()
        return models.filter { !$0.name.isEmpty && seen.insert($0.name).inserted }.sorted(by: OllamaCloudModel.newer)
    }
}
