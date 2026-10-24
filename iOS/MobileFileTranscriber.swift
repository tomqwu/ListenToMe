import Foundation
import ListenToMeCore

typealias WatchAudioChunk = LocalAudioChunk

/// Transcribes a recording's audio files. Contract: chunks are fed in order into one analysis
/// session, so a word spanning two chunks is not cut; each final result is delivered with times
/// relative to the recording start; the call returns only after everything fed is finalized; and
/// cancellation stops it promptly and throws `CancellationError`, delivering nothing after it.
/// An error thrown by `onFinal` stops the transcription and is rethrown.
@MainActor
protocol WatchAudioTranscribing: AnyObject {
    func transcribe(_ chunks: [WatchAudioChunk], locale: Locale,
                    onFinal: @escaping @MainActor (TranscriptSegment) throws -> Void) async throws
    /// The vocabularies' recognition terms for the next `transcribe` (issue #222).
    func setContextualStrings(_ strings: [String])
}

extension WatchAudioTranscribing {
    func setContextualStrings(_ strings: [String]) {}
}

@MainActor
final class MobileFileTranscriber: WatchAudioTranscribing {
    static let speakerName = "Apple Watch"
    private let reader = LocalAudioFileTranscriber(source: .you, speakerName: speakerName)
    func setContextualStrings(_ strings: [String]) { reader.setContextualStrings(strings) }
    func transcribe(_ chunks: [WatchAudioChunk], locale: Locale,
                    onFinal: @escaping @MainActor (TranscriptSegment) throws -> Void) async throws {
        try await reader.transcribe(chunks, locale: locale, onFinal: onFinal)
    }
}
