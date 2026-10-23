import Foundation

/// Lists the models an OpenAI-compatible server offers (`GET <base>/models`). The list is only what
/// the server reports; `/v1/models` says nothing about capabilities or where a model runs.
public struct OpenAICompatibleCatalog: Sendable {
    /// Cap on the response body; OpenRouter's full catalog is well under this.
    public static let maximumBytes = 4 * 1024 * 1024
    /// Cap on how many model IDs are kept.
    public static let maximumModels = 2_000

    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    /// Fetches and parses the model list. Redirects are refused and the key is sent only to `baseURL`.
    public func fetch(baseURL: URL, apiKey: String?) async throws -> [String] {
        do {
            let request = OpenAICompatibleTransport.request(
                OpenAICompatibleEndpoint.modelsURL(baseURL), apiKey: apiKey, timeout: 15)
            let (bytes, _) = try await OpenAICompatibleTransport.open(request, session: session, apiKey: apiKey)
            let body = try await OpenAICompatibleTransport.collect(bytes, limit: Self.maximumBytes, throwing: true)
            return try Self.parse(body)
        } catch {
            throw OpenAICompatibleTransport.mapped(error, host: baseURL, apiKey: apiKey)
        }
    }

    /// `{"data":[{"id":"…"}, …]}` → unique, non-empty IDs in numeric-aware alphabetical order.
    /// Malformed entries are skipped; a body that is not a model list at all throws.
    public static func parse(_ data: Data) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAICompatibleError.invalidModelList
        }
        if let message = OpenAICompatibleSSE.errorMessage(in: object) { throw OpenAICompatibleError.server(message) }
        guard let entries = object["data"] as? [[String: Any]] else { throw OpenAICompatibleError.invalidModelList }
        var seen = Set<String>()
        let ids = entries.compactMap { $0["id"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isPlausibleID($0) && seen.insert($0).inserted }
        return Array(ids.sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
            .prefix(maximumModels))
    }

    /// A model ID is shown in settings and sent back verbatim, so control characters and absurd
    /// lengths are dropped rather than rendered.
    static func isPlausibleID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 256 && !id.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
