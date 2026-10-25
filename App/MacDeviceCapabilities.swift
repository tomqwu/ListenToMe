import Foundation
import Speech
import ListenToMeCore

/// Prompt-free native metadata. Permission requests, downloads and microphone activation stay in Start.
@MainActor
enum MacDeviceCapabilities {
    static func recording(engine: String, locale: Locale, checkMicrophone: Bool = true) async -> FeatureAvailability {
        let microphone: MicrophoneAuthorization = checkMicrophone
            ? PermissionsModel.currentMicrophoneAuthorization() : .authorized
        let advanced = engine != "speechRecognizer" && engine != "whisperKit" && SpeechTranscriber.isAvailable
            ? await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil : false
        let legacy = engine == "speechRecognizer" && SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true
        let speechPermission = SFSpeechRecognizer.authorizationStatus()
        return MacFeatureReadiness.recording(engine: engine, microphone: microphone,
            advancedSupported: advanced, legacySupported: legacy,
            legacyPermissionDenied: speechPermission == .denied || speechPermission == .restricted)
    }

    static func appleReason(locale: Locale) -> String? {
        AppleIntelligenceProvider.unavailableReason ?? AppleIntelligenceProvider.unsupportedLocaleReason(for: locale)
    }
}
