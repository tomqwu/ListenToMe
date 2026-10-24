import Foundation
import Observation
import ListenToMeCore

/// Stages recognition off to the side. No archive or conversation is modified until the user reviews
/// the complete result and explicitly chooses Replace transcript.
@MainActor @Observable
final class SavedAudioRetranscription {
    typealias Recognize = @MainActor (URL, SavedAudioRun, String, [String]) async throws -> [TranscriptSegment]
    private(set) var isRunning = false
    private(set) var progress = ""
    private(set) var error: String?
    private(set) var preview: ConversationRetranscription?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func start(original: SessionRecord, library: SavedAudioLibrary, language: String, terms: [String],
               recognize: @escaping Recognize) {
        cancel()
        let token = generation
        let runs = ConversationRetranscription.timeline(for: library.runs(for: original.id))
        guard !runs.isEmpty else { error = "This conversation has no saved audio."; return }
        isRunning = true
        error = nil
        task = Task {
            do {
                var lines: [TranscriptSegment] = []
                for (index, run) in runs.enumerated() {
                    try Task.checkCancellation()
                    guard let url = library.url(for: run, conversationID: original.id),
                          FileManager.default.fileExists(atPath: url.path) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    progress = "Transcribing part \(index + 1) of \(runs.count)…"
                    let recognized = try await recognize(url, run, language, terms)
                    try Task.checkCancellation()
                    // A track with no recognized speech may be silence. Never replace anything if
                    // the combined result is empty, and never publish partial results after an error.
                    lines += try ConversationRetranscription.placing(recognized, run: run, language: language)
                }
                guard generation == token else { return }
                preview = try ConversationRetranscription(original: original, segments: lines, language: language, audioRuns: runs)
            } catch {
                guard generation == token else { return }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
            guard generation == token else { return }
            isRunning = false
            task = nil
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
        isRunning = false; preview = nil; error = nil; progress = ""
    }
}
