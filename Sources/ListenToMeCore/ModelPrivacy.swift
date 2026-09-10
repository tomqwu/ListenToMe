import Foundation

public enum AIProcessingMode: String, CaseIterable, Sendable {
    case off, local, cloud
    public var label: String {
        switch self {
        case .off: return "AI off — transcript only"
        case .local: return "Local models only"
        case .cloud: return "Ollama Cloud — sends transcript and context"
        }
    }
}

public enum ModelPrivacy {
    /// Fail closed on missing/remote metadata. A localhost URL or a model name alone is insufficient.
    public static func isVerifiedLocal(_ data: Data) -> Bool {
        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              info["remote_host"] == nil, info["remote_model"] == nil,
              let details = info["details"] as? [String: Any],
              let format = details["format"] as? String, !format.isEmpty,
              let modelInfo = info["model_info"] as? [String: Any], !modelInfo.isEmpty else { return false }
        return true
    }
}
