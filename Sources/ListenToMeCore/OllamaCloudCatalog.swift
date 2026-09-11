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

public struct OllamaCloudCatalog: Sendable {
    public static let baseURL = URL(string: "https://ollama.com")!
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(apiKey: String) async throws -> [OllamaCloudModel] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaStreamError.server("Model catalog returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        struct Catalog: Decodable { let models: [OllamaCloudModel] }
        let models = try JSONDecoder().decode(Catalog.self, from: data).models
        var seen = Set<String>()
        return models.filter { !$0.name.isEmpty && seen.insert($0.name).inserted }.sorted(by: OllamaCloudModel.newer)
    }
}
