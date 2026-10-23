import Foundation

/// A validated edit of the OpenAI-compatible server and key, computed before anything is written so
/// a settings save is all-or-nothing (issue #52). The key is bound to the server origin: storing a
/// key records that origin, and moving to another origin removes a key that was not re-entered.
public struct OpenAICompatibleSettingsChange: Equatable, Sendable {
    public enum KeyAction: Equatable, Sendable {
        case keep
        case store(key: String, origin: String)
        case remove
    }

    /// The normalized API base to save, or empty for no server.
    public let baseURL: String
    public let keyAction: KeyAction

    /// Throws `OpenAICompatibleEndpoint.ValidationError` without side effects when the input is invalid.
    public static func plan(rawURL: String, key: String, keyEdited: Bool,
                            currentBaseURL: String) throws -> Self {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.isEmpty ? nil : try OpenAICompatibleEndpoint.normalize(trimmed)
        let newOrigin = url.map(OpenAICompatibleEndpoint.origin)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let action: KeyAction
        if keyEdited {
            if trimmedKey.isEmpty {
                action = .remove
            } else {
                guard let newOrigin else { throw OpenAICompatibleEndpoint.ValidationError.keyWithoutServer }
                action = .store(key: trimmedKey, origin: newOrigin)
            }
        } else {
            let oldOrigin = (try? OpenAICompatibleEndpoint.normalize(currentBaseURL)).map(OpenAICompatibleEndpoint.origin)
            action = newOrigin == oldOrigin ? .keep : .remove
        }
        return Self(baseURL: url?.absoluteString ?? "", keyAction: action)
    }
}
