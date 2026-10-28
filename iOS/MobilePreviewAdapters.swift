#if DEBUG && targetEnvironment(simulator)
import Foundation
import ListenToMeCore

/// Explicit preview adapters keep lifecycle-aware fixtures independent of device models and audio.
struct PreviewDiarizer: MobileSpeakerDiarizing {
    func diarize(samples: [Float]) async throws -> DiarizedWindow { DiarizedWindow(segments: []) }
    func retryModelLoad() async {}
    func prepareModels() async throws {}
}

@MainActor
final class PreviewRecorder: MobileRecording {
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {}
    func stop() async throws {}
    func reconfigure() async throws {}
}

/// A manual Refresh in a preview keeps its authored answer and never reaches a configured server.
struct PreviewProvider: LLMProvider {
    let answer: String
    let id = "preview-no-network"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }
}
#endif
