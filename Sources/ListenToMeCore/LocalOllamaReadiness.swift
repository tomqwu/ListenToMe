import Foundation

/// Distinguishes an unavailable catalog from an empty installation and unverified capabilities.
/// A failed probe must never tell the user their installed model is missing.
public struct LocalOllamaReadiness: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case unavailable, noModels, noChatModels, unverified, ready }
    public let installed: Set<String>?
    public let available: Set<String>
    public let unverified: Set<String>
    public init(installed: [String]?, available: [String] = [], unverified: Set<String> = []) {
        self.installed = installed.map(Set.init)
        self.available = Set(available)
        self.unverified = unverified
    }
    public var status: Status {
        guard let installed else { return .unavailable }
        if installed.isEmpty { return .noModels }
        if !available.isEmpty { return .ready }
        return unverified.isEmpty ? .noChatModels : .unverified
    }
    public var message: String {
        switch status {
        case .unavailable:
            return "Could not reach local Ollama or read its model list. Open Ollama, or install it, then retry."
        case .noModels:
            return "Ollama is running, but no models are installed. Download a chat model, then retry."
        case .noChatModels:
            return "Ollama is running, but none of its installed models is verified as a local chat model."
        case .unverified:
            return "Ollama is running, but model capabilities could not be verified. Retry; installed choices are kept."
        case .ready:
            let ready = "Ready: \(available.count) local chat model(s)."
            return unverified.isEmpty ? ready : ready + " \(unverified.count) other model(s) could not be verified."
        }
    }
    public var needsModel: Bool { status == .noModels || status == .noChatModels }
    public static let pullCommand = "ollama pull llama3.2"
    public func label(for model: String) -> String {
        if available.contains(model) { return model }
        guard let installed else { return model + " (not verified)" }
        if !installed.contains(model) { return model + " (not installed)" }
        if unverified.contains(model) { return model + " (not verified)" }
        return model + " (not a local chat model)"
    }
}
