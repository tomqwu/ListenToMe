import Foundation

/// The policy the Mac's native capability adapter and controls apply before offering an action.
public enum MacFeatureReadiness {
    public static func selectableAIModes(appleReason: String?) -> [AIProcessingMode] {
        AIProcessingMode.allCases.filter { $0 != .apple || appleReason == nil }
    }

    public static func selectAI(_ requested: AIProcessingMode, current: AIProcessingMode,
                                appleReason: String?) -> AIProcessingMode {
        requested == .apple && appleReason != nil ? current : requested
    }

    public static func recording(engine: String, microphone: MicrophoneAuthorization,
                                 advancedSupported: Bool, legacySupported: Bool,
                                 legacyPermissionDenied: Bool) -> FeatureAvailability {
        if case .blocked(let reason, let canOpenSettings) = CapturePreflight.decide(microphone: microphone) {
            return canOpenSettings ? .setupRequired(reason: reason, action: "Open microphone settings")
                : .unsupported(reason: reason)
        }
        switch engine {
        case "whisperKit": return .ready   // Its model is prepared/downloaded only after an explicit Start.
        case "speechRecognizer":
            guard legacySupported else {
                return .unsupported(reason: "SpeechRecognizer has no on-device support on this Mac or for this language. " +
                                    "Choose another language or engine in Settings.")
            }
            if legacyPermissionDenied {
                return .setupRequired(reason: "Speech recognition permission is off. Allow ListenToMe in " +
                                      "System Settings → Privacy & Security → Speech Recognition, or choose another engine.",
                                      action: "Open speech recognition settings")
            }
            return .ready
        default:
            return advancedSupported ? .ready : .unsupported(reason: "SpeechAnalyzer is unavailable on this Mac or " +
                "for this language. Choose a supported language, SpeechRecognizer or WhisperKit in Settings.")
        }
    }

    public static func aiCanRun(mode: AIProcessingMode, appleReason: String?) -> Bool {
        mode != .off && (mode != .apple || appleReason == nil)
    }
}
