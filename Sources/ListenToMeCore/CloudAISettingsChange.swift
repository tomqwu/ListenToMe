import Foundation

/// A validated edit of the cloud AI service and its key on macOS, computed before anything is
/// written so a settings save stays all-or-nothing (issue #214, as #52's
/// `OpenAICompatibleSettingsChange`). A key is stored for one vendor only, bound to that vendor's origin.
public struct CloudAISettingsChange: Equatable, Sendable {
    public enum ValidationError: LocalizedError, Equatable {
        case noService
        case keyWithoutService

        public var errorDescription: String? {
            switch self {
            case .noService: return "Choose a cloud AI service, or pick another AI processing mode."
            case .keyWithoutService: return "Choose the cloud AI service this API key belongs to."
            }
        }
    }

    public enum KeyAction: Equatable, Sendable {
        case keep
        case store(key: String, account: String, origin: String)
        case remove(account: String)
    }

    /// The service to remember, or nil to keep the current one.
    public let vendor: CloudAIPreset.ID?
    public let keyAction: KeyAction

    /// Throws without side effects when the edit cannot be saved. `keyEdited` is whether the key field
    /// differs from the key saved for `vendor`.
    public static func plan(usesCloudAI: Bool, vendor: CloudAIPreset.ID?, key: String,
                            keyEdited: Bool) throws -> Self {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let vendor else {
            if usesCloudAI { throw ValidationError.noService }
            if keyEdited && !trimmed.isEmpty { throw ValidationError.keyWithoutService }
            return Self(vendor: nil, keyAction: .keep)
        }
        let preset = CloudAIPreset.preset(vendor)
        guard keyEdited else { return Self(vendor: vendor, keyAction: .keep) }
        return Self(vendor: vendor, keyAction: trimmed.isEmpty
            ? .remove(account: preset.keychainAccount)
            : .store(key: trimmed, account: preset.keychainAccount, origin: preset.origin))
    }
}
