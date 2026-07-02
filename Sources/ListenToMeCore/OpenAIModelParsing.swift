import Foundation

/// Pure parsing of an OpenAI-compatible `/v1/models` response body.
public enum OpenAIModelParsing {
    /// Returns the model ids from `{ "data": [ { "id": ... } ] }`. Empty on garbage / empty / missing.
    public static func ids(from data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["id"] as? String }
    }
}
