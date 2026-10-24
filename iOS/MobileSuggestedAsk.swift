import Foundation
import ListenToMeCore
import Observation

/// A tapped suggestion's question and its answer (#61), shown in the Ask card under Quick Summary.
/// It is deliberately not a summary: it never replaces Quick Summary or Summary on screen or in the saved
/// conversation, never counts as a completed review, and never touches Auto's queued reviews or
/// recommendations. The answer lives only in memory, under its question, until it is closed, a new
/// conversation starts or the provider changes.
@MainActor @Observable
final class MobileSuggestedAsk {
    static let maximumAnswerCharacters = 100_000
    private(set) var question: String?
    private(set) var answer = ""
    private(set) var isAnswering = false
    private(set) var error: String?
    /// Which part of the conversation the answer read, when not all of it fitted (`OnDemandGrounding`).
    private(set) var grounding: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Streams `request` to `client` under `question`, replacing any earlier ask. `answered` runs only
    /// when a complete, non-empty answer arrived — never on a failure or cancellation.
    func start(question: String, request: LLMRequest, grounding: String? = nil, client: any LLMProvider,
               answered: @escaping @MainActor () -> Void) {
        cancel()
        generation += 1
        let token = generation
        self.question = question; self.grounding = grounding
        answer = ""; error = nil; isAnswering = true
        task = Task { [weak self] in
            do {
                var text = ""
                for try await delta in client.stream(request) {
                    try Task.checkCancellation()
                    text += delta
                    guard text.count <= Self.maximumAnswerCharacters else {
                        throw QuickSummaryError.message("The answer was too large.")
                    }
                    guard let self, self.generation == token else { return }
                    self.answer = text
                }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.isAnswering = false; self.task = nil
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.error = "No answer came back. Try again."
                } else {
                    answered()
                }
            } catch {
                guard let self, self.generation == token, !(error is CancellationError) else { return }
                self.isAnswering = false; self.task = nil
                self.error = "Could not answer: \(MobileAISettings.errorMessage(error))"
            }
        }
    }

    /// Stops an answer in progress and keeps what already arrived.
    func cancel() {
        generation += 1
        task?.cancel(); task = nil
        isAnswering = false
    }

    /// Removes the question and its answer.
    func reset() {
        cancel()
        question = nil; answer = ""; error = nil; grounding = nil
    }

    /// Test-only: waits for the answer in progress.
    func waitForAnswer() async { await task?.value }
}
