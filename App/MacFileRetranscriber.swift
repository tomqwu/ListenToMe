import Foundation
import ListenToMeCore

@MainActor
enum MacFileRetranscriber {
    static func recognize(url: URL, run: SavedAudioRun, language: String, terms: [String]) async throws -> [TranscriptSegment] {
        guard let producer = AudioFileChunkProducer(url: url, source: run.source) else {
            throw LocalAudioFileError.message("Could not read the saved audio file.")
        }
        let transcriber = WhisperKitTranscriber(locale: Locale(identifier: language))
        var lines: [TranscriptSegment] = []
        let drain = Task { for await line in transcriber.segments where line.isFinal { lines.append(line) } }
        return try await withTaskCancellationHandler {
            do {
                await transcriber.prepare()
                var started = ContinuousClock.now
                var seconds = 0.0
                var fed = false
                while !Task.isCancelled, let chunk = try await producer.next() {
                    await transcriber.feed(chunk)
                    if !fed { started = .now; fed = true }
                    seconds += Double(chunk.samples.count) / max(1, chunk.sampleRate)
                    // Pace long files like the existing import path; model setup is excluded.
                    let elapsed = Double(started.duration(to: .now).components.seconds)
                    let lead = seconds - elapsed * 8
                    if lead > 8 { try? await Task.sleep(for: .seconds(min(lead, 5))) }
                }
                await transcriber.finish()
                await drain.value
                try Task.checkCancellation()
                if let failure = await transcriber.failure { throw LocalAudioFileError.message(failure) }
                return lines
            } catch {
                await transcriber.cancel()
                await drain.value
                throw error
            }
        } onCancel: {
            Task { await transcriber.cancel() }
        }
    }
}
