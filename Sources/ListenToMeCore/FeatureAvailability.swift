/// Runtime feature readiness shared by platform adapters. Describes a feature, not a device-name list.
public enum FeatureAvailability: Equatable, Sendable {
    case ready
    case setupRequired(reason: String, action: String)
    case temporarilyUnavailable(reason: String)
    case unsupported(reason: String)

    /// Configuring this feature is distinct from opening Settings to choose a supported alternative.
    public var canConfigure: Bool {
        if case .unsupported = self { return false }
        return true
    }
    public var canRun: Bool { self == .ready }
    public var reason: String? {
        switch self {
        case .ready: nil
        case .setupRequired(let reason, _), .temporarilyUnavailable(let reason), .unsupported(let reason): reason
        }
    }
    public var setupAction: String? {
        if case .setupRequired(_, let action) = self { return action }
        return nil
    }
}
