import Foundation
import Observation
import ListenToMeCore

@MainActor @Observable
final class MobileTranscriptCorrector {
    private struct Job {
        let segment: TranscriptSegment
        let context: String
        let model: String
        let provider: any LLMProvider
        let apply: (TranscriptSegment) -> Void
    }
    private var queue: [Job] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private(set) var working = false
    private(set) var status = "Checks new completed phrases."

    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil; queue = []; working = false
        status = "Checks new completed phrases."
    }

    func reportFailure(_ error: Error) { status = "Original kept · \(MobileAISettings.errorMessage(error))" }

    func submit(_ segment: TranscriptSegment, context: String, model: String, provider: any LLMProvider,
                apply: @escaping (TranscriptSegment) -> Void) {
        guard segment.isFinal, !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard segment.text.count <= 1_200 else {
            status = "Long phrase kept as heard. Shorter phrases will still be checked."
            return
        }
        if queue.count >= 6 { queue.removeFirst() }
        queue.append(Job(segment: segment, context: context, model: model, provider: provider, apply: apply))
        guard task == nil else { return }
        let token = generation
        working = true
        task = Task { [weak self] in
            // Small coalescing delay; independent of the summary timer and microphone.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self else { return }
            while !queue.isEmpty, generation == token, !Task.isCancelled {
                let job = queue.removeFirst()
                status = "Checking speech…"
                do {
                    let text = try await Self.correct(job.segment.text, context: job.context, provider: job.provider)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    if text != job.segment.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                        job.apply(job.segment.withCorrection(text, model: job.model))
                        status = "Correction applied · Tap AI corrected to review."
                    } else { status = "Checked · Original wording kept." }
                } catch {
                    guard generation == token, !Task.isCancelled else { return }
                    status = "Original kept · \(MobileAISettings.errorMessage(error))"
                }
            }
            if generation == token { task = nil; working = false }
        }
    }

    /// Bound the entire request, including providers that never produce a first token.
    static func correct(_ text: String, context: String, provider: any LLMProvider,
                        timeout: Duration = .seconds(12)) async throws -> String {
        let request = try MobileTranscriptCorrection.request(text: text, context: context)
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var response = ""
                for try await delta in provider.stream(request) {
                    try Task.checkCancellation()
                    response += delta
                    guard response.utf8.count <= 8_192 else { throw RecordingError.message("Correction response was too large.") }
                }
                try Task.checkCancellation()
                return try MobileTranscriptCorrection.validatedText(response, original: text)
            }
            group.addTask { try await Task.sleep(for: timeout); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}
