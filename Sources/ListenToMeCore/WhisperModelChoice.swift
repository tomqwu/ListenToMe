import Foundation

/// Explicit multilingual choices. Existing installs keep Base; unknown or obsolete preferences
/// cannot silently select an unrelated model or cause an arbitrary download.
public enum WhisperModelChoice: String, CaseIterable, Identifiable, Sendable {
    case tiny, base, small
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var tradeoff: String {
        switch self {
        case .tiny: return "Smallest download and lightest processing; more recognition errors are possible."
        case .base: return "Default balance of download size, processing cost and recognition quality."
        case .small: return "Larger download and more processing; may improve recognition quality."
        }
    }
    public static func load(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: "whisperModelSize").flatMap(Self.init(rawValue:)) ?? .base
    }
    public func save(to defaults: UserDefaults) { defaults.set(rawValue, forKey: "whisperModelSize") }
    public func matchesLoadedVariant(_ variant: String) -> Bool { variant == rawValue }
}
