import AVFoundation
import Foundation
import Speech
import ListenToMeCore

/// One local audio chunk on disk, placed on the recording's timeline (issue #181).
struct LocalAudioChunk: Sendable, Equatable {
    let index: Int
    let url: URL
    /// Seconds from the start of the recording to this chunk's first sample.
    let startOffset: TimeInterval
    let duration: TimeInterval
}

enum LocalAudioFileError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// On-device file transcription shared by Watch imports and saved-audio re-transcription.
@MainActor
final class LocalAudioFileTranscriber {
    private let source: SpeakerSource
    private let speakerName: String?
    init(source: SpeakerSource = .you, speakerName: String? = nil) {
        self.source = source; self.speakerName = speakerName
    }
    private var contextualStrings: [String] = []

    func setContextualStrings(_ strings: [String]) { contextualStrings = strings }

    #if os(iOS)
    static func prepare(locale: Locale, environment: MobileSpeechModel.Environment = .init()) async throws
        -> (MobilePreparedTranscriber, AVAudioFormat) {
        try await MobileSpeechModel.prepare(locale: locale, volatileResults: false, environment: environment)
    }
    #else
    private static func prepare(locale: Locale) async throws -> (SpeechTranscriber, AVAudioFormat) {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw LocalAudioFileError.message("On-device transcription is unavailable for this language.")
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw LocalAudioFileError.message("The speech model has no supported audio format.")
        }
        return (transcriber, format)
    }

    #endif

    func transcribe(_ chunks: [LocalAudioChunk], locale: Locale,
                    onFinal: @escaping @MainActor (TranscriptSegment) throws -> Void) async throws {
        guard !chunks.isEmpty else { return }
        #if targetEnvironment(simulator)
        throw LocalAudioFileError.message("On-device file transcription requires a physical iPhone or iPad.")
        #else
        try Task.checkCancellation()
        // Finals only: nothing is shown live, and only final text is saved.
        let (transcriber, format) = try await Self.prepare(locale: locale)
        try Task.checkCancellation()
        #if os(iOS)
        let analyzer = SpeechAnalyzer(modules: [transcriber.module])
        #else
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        #endif
        if !contextualStrings.isEmpty { await SpeechVocabularyContext.apply(contextualStrings, to: analyzer) }
        try await analyzer.prepareToAnalyze(in: format)
        let feed = ChunkFeed(chunks: chunks, format: format)
        let results = Task { @MainActor in
            #if os(iOS)
            _ = try await transcriber.consume { result in
                guard !feed.isStopped else { return false }
                let text = String(result.text.characters)
                guard result.isFinal, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
                do {
                    try onFinal(TranscriptSegment(source: self.source, text: text, isFinal: true,
                                                  start: result.range.start.seconds, end: result.range.end.seconds,
                                                  speakerName: self.speakerName))
                } catch {
                    feed.stop(failing: error)
                    throw error
                }
                return true
            }
            #else
            for try await result in transcriber.results {
                guard !feed.isStopped else { return }
                let text = String(result.text.characters)
                guard result.isFinal, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                do {
                    try onFinal(TranscriptSegment(source: self.source, text: text, isFinal: true,
                                                  start: result.range.start.seconds, end: result.range.end.seconds,
                                                  speakerName: self.speakerName))
                } catch {
                    feed.stop(failing: error)
                    throw error
                }
            }
            #endif
        }
        let strings = contextualStrings
        do {
            try await withTaskCancellationHandler {
                try await analyzer.start(inputSequence: ChunkInputs(feed: feed))
                // Again after start: a context set before it is not documented to survive it.
                if !strings.isEmpty { await SpeechVocabularyContext.apply(strings, to: analyzer) }
                // The feed ends after the last chunk, or as soon as it is stopped.
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                try await results.value
            } onCancel: {
                feed.stop(failing: nil)
                results.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            feed.stop(failing: nil)
            results.cancel()
            await analyzer.cancelAndFinishNow()
            if Task.isCancelled { throw CancellationError() }
            throw feed.failure ?? error
        }
        if Task.isCancelled { throw CancellationError() }
        if let failure = feed.failure { throw failure }
        #endif
    }
}

