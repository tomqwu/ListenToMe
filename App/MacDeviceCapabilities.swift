import Foundation
import Speech
import ListenToMeCore

/// Prompt-free native metadata. Permission requests, downloads and microphone activation stay in Start.
@MainActor
enum MacDeviceCapabilities {
    struct Environment {
        var microphone: () -> MicrophoneAuthorization = { PermissionsModel.currentMicrophoneAuthorization() }
        var advancedAvailable: () -> Bool = { SpeechTranscriber.isAvailable }
        var advancedLocale: (Locale) async -> Bool = { await SpeechTranscriber.supportedLocale(equivalentTo: $0) != nil }
        var legacySupported: (Locale) -> Bool = { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
        var legacyPermissionDenied: () -> Bool = {
            let status = SFSpeechRecognizer.authorizationStatus()
            return status == .denied || status == .restricted
        }
    }

    static func recording(engine: String, locale: Locale, checkMicrophone: Bool = true,
                          environment: Environment = Environment()) async -> FeatureAvailability {
        let microphone: MicrophoneAuthorization = checkMicrophone
            ? environment.microphone() : .authorized
        let advanced = engine != "speechRecognizer" && engine != "whisperKit" && environment.advancedAvailable()
            ? await environment.advancedLocale(locale) : false
        let legacy = engine == "speechRecognizer" && environment.legacySupported(locale)
        return MacFeatureReadiness.recording(engine: engine, microphone: microphone,
            advancedSupported: advanced, legacySupported: legacy,
            legacyPermissionDenied: environment.legacyPermissionDenied())
    }

    static func appleReason(locale: Locale) -> String? {
        AppleIntelligenceProvider.unavailableReason ?? AppleIntelligenceProvider.unsupportedLocaleReason(for: locale)
    }
}
