import AVFoundation
import Speech

/// The preparation live recording and Apple Watch file transcription share (issue #181): a
/// supported locale, the on-device model's assets, and the analyzer's best audio format.
@MainActor
enum MobileSpeechModel {
    static func prepare(locale: Locale, volatileResults: Bool) async throws -> (SpeechTranscriber, AVAudioFormat) {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw RecordingError.message("On-device transcription is unavailable for this device or language. Try another language.")
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                            reportingOptions: volatileResults ? [.volatileResults] : [],
                                            attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw RecordingError.message("The speech model has no supported audio format.")
        }
        return (transcriber, format)
    }

    /// Live recording and file transcription both refuse in the simulator with this message.
    static let simulatorUnavailable = "Live transcription is unavailable in the iPhone simulator. " +
        "Run ListenToMe on a physical iPhone or iPad to record. Microphone permission will not fix this; " +
        "notes, history and export still work here."
}
