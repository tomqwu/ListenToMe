import Foundation

/// An inconclusive probe is different from a model positively known not to support this route.
public struct OllamaModelCapability: Sendable, Equatable {
    public enum Status: Sendable { case chat, notChat, unverified }
    public let status: Status
    public let verifiedLocal: Bool
    public var chatCapable: Bool { status == .chat }

    public init(status: Status = .unverified, verifiedLocal: Bool = false) {
        self.status = status; self.verifiedLocal = verifiedLocal
    }

    public init(metadata: Data, localOnly: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let capabilities = object["capabilities"] as? [String] else {
            self.init(); return
        }
        let local = ModelPrivacy.isVerifiedLocal(metadata)
        guard capabilities.contains("completion") else {
            self.init(status: .notChat, verifiedLocal: local); return
        }
        if localOnly && !local {
            let remote = object["remote_host"] != nil || object["remote_model"] != nil
            self.init(status: remote ? .notChat : .unverified); return
        }
        self.init(status: .chat, verifiedLocal: local)
    }
}
