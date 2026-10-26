import AVFoundation
import Speech
import ListenToMeCore

/// The preparation live recording and Apple Watch file transcription share (issue #181): a
/// supported locale, the on-device model's assets, and the analyzer's best audio format.
@MainActor
enum MobileSpeechModel {
    /// Framework boundaries are replaceable in native tests; production uses only local modules.
    struct Environment {
        var speechAvailable: () -> Bool = { SpeechTranscriber.isAvailable }
        var speechLocale: (Locale) async -> Locale? = { await SpeechTranscriber.supportedLocale(equivalentTo: $0) }
        var dictationLocale: (Locale) async -> Locale? = { await DictationTranscriber.supportedLocale(equivalentTo: $0) }
        var install: (any SpeechModule) async throws -> Void = { module in
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await installation.downloadAndInstall()
            }
        }
        var format: (any SpeechModule) async -> AVAudioFormat? = {
            await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [$0])
        }
    }

    static func availability(locale: Locale, environment: Environment = Environment(),
                             simulator: Bool = isSimulator,
                             microphoneDenied: Bool = AVAudioApplication.shared.recordPermission == .denied) async -> FeatureAvailability {
        if simulator { return .unsupported(reason: simulatorUnavailable) }
        if microphoneDenied {
            return .setupRequired(reason: "Microphone access is off. Allow ListenToMe in Settings to record.",
                                  action: "Open microphone settings")
        }
        if environment.speechAvailable(), await environment.speechLocale(locale) != nil { return .ready }
        if await environment.dictationLocale(locale) != nil { return .ready }
        return .unsupported(reason: "On-device transcription is unavailable for this device or language. " +
                            "Choose another transcription language in Settings. Notes, history and export still work.")
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func prepare(locale: Locale, volatileResults: Bool,
                        environment: Environment = Environment()) async throws -> (MobilePreparedTranscriber, AVAudioFormat) {
        let transcriber: MobilePreparedTranscriber
        if environment.speechAvailable(), let supported = await environment.speechLocale(locale) {
            transcriber = MobilePreparedTranscriber(SpeechTranscriber(
                locale: supported, transcriptionOptions: [], reportingOptions: volatileResults ? [.volatileResults] : [],
                attributeOptions: [.audioTimeRange]), text: { $0.text })
        } else if let supported = await environment.dictationLocale(locale) {
            transcriber = MobilePreparedTranscriber(DictationTranscriber(
                locale: supported, contentHints: [], transcriptionOptions: [],
                reportingOptions: volatileResults ? [.volatileResults] : [],
                attributeOptions: [.audioTimeRange]), text: { $0.text })
        } else {
            throw RecordingError.message("On-device transcription is unavailable for this device or language. Try another language.")
        }
        try await environment.install(transcriber.module)
        try Task.checkCancellation()
        guard let format = await environment.format(transcriber.module) else {
            throw RecordingError.message("The speech model has no supported audio format.")
        }
        return (transcriber, format)
    }

    /// Live recording and file transcription both refuse in the simulator with this message.
    static let simulatorUnavailable = "Live transcription is unavailable in the iPhone simulator. " +
        "Run ListenToMe on a physical iPhone or iPad to record. Microphone permission will not fix this; " +
        "notes, history and export still work here."
}
