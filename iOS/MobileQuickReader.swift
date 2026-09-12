import Foundation
import ListenToMeCore
import Observation

struct MobileQuickDecision: Decodable, Sendable {
    let action: String
    let context: String
    let bullets: [String]
    let reviews: [Review]
    struct Review: Codable, Equatable, Sendable {
        let mode: String
        let confidence: String
        let reason: String
    }
    var summary: String? { action == "publish" ? bullets.map { "- " + $0 }.joined(separator: "\n") : nil }

    static func parse(_ response: String) throws -> Self {
        var answer = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.hasSuffix("```") { answer = String(answer.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard answer.hasSuffix("}") else { throw invalidResponse }
        // Some Cloud Flash models prepend reasoning even with thinking disabled. Only accept a
        // complete, strictly shaped final object; never render partial JSON or the preamble.
        for start in answer.indices.reversed().filter({ answer[$0] == "{" }).prefix(64) {
            let data = Data(answer[start...].utf8)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == Set(["action", "context", "bullets", "reviews"]),
                  let result = try? JSONDecoder().decode(Self.self, from: data) else { continue }
            guard ["keep", "publish"].contains(result.action), result.context.count <= 2_000,
                  result.reviews.count <= 2, Set(result.reviews.map(\.mode)).count == result.reviews.count,
                  result.reviews.allSatisfy({ ["summary", "deep"].contains($0.mode)
                      && ["low", "medium", "high"].contains($0.confidence)
                      && !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.reason.count <= 160 }),
                  result.bullets.count <= 5, result.bullets.joined().count <= 1_500,
                  result.bullets.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.contains("\n") }),
                  result.action == "keep" ? result.bullets.isEmpty : !result.bullets.isEmpty else { throw invalidResponse }
            return result
        }
        throw invalidResponse
    }
    private static var invalidResponse: RecordingError { .message("The model did not return a usable Quick Summary update.") }
}

@MainActor @Observable
final class MobileQuickReader {
    private(set) var context = MobileQuickContext()
    private(set) var isReading = false
    private(set) var error: String?
    private(set) var unchanged = false
    private(set) var completedReads = 0
    private(set) var failures = 0
    private(set) var recommendations: [MobileQuickDecision.Review] = []
    private(set) var reviewsCompleted: [String] = []
    private var pendingOutput: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil; isReading = false
    }

    func reset() {
        cancel(); context = MobileQuickContext(); error = nil; unchanged = false; completedReads = 0; failures = 0
        recommendations = []; reviewsCompleted = []; pendingOutput = nil
    }

    func markReviewed(_ mode: MobileSummaryMode) {
        guard mode != .quick else { return }
        recommendations.removeAll { $0.mode == mode.rawValue }
        if !reviewsCompleted.contains(mode.rawValue) { reviewsCompleted.append(mode.rawValue) }
    }

    func clearError() { error = nil; failures = 0 }

    func read(_ batch: MobileQuickContext.Batch, provider: any LLMProvider,
              isCurrent: @escaping () -> Bool, apply: @escaping (String) -> Void) async {
        guard task == nil else { return }
        let token = generation
        let completedBeforeRead = reviewsCompleted
        isReading = true
        task = Task {
            defer { if generation == token { isReading = false; task = nil } }
            do {
                let decision = try await Self.evaluate(batch.request, provider: provider)
                try Task.checkCancellation()
                guard generation == token, isCurrent() else { return }
                context.accept(batch, memory: decision.context)
                error = nil; failures = 0; completedReads += 1
                // A manual review may finish during this evaluation. Do not resurrect its stale suggestion.
                let completedDuringRead = Set(reviewsCompleted).subtracting(completedBeforeRead)
                recommendations = []
                for action in MobileSummaryScheduler.actions(for: decision) {
                    switch action {
                    case .keepQuick:
                        unchanged = true
                        if !batch.hasMore, let output = pendingOutput { apply(output); pendingOutput = nil; unchanged = false }
                    case .publishQuick(let output):
                        unchanged = false
                        if batch.hasMore { pendingOutput = output } else { apply(output); pendingOutput = nil }
                    case .suggestReview(let review):
                        if !batch.hasMore, !completedDuringRead.contains(review.mode) { recommendations.append(review) }
                    }
                }
                reviewsCompleted.removeAll { completedBeforeRead.contains($0) }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                failures += 1
                self.error = "Quick Summary check failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept."
            }
        }
        await task?.value
    }

    static func evaluate(_ request: LLMRequest, provider: any LLMProvider,
                         timeout: Duration = .seconds(15)) async throws -> MobileQuickDecision {
        try await withThrowingTaskGroup(of: MobileQuickDecision.self) { group in
            group.addTask {
                var response = ""
                for try await delta in provider.stream(request) {
                    try Task.checkCancellation()
                    response += delta
                    guard response.utf8.count <= 16_384 else { throw RecordingError.message("Quick Summary response was too large.") }
                }
                try Task.checkCancellation()
                return try MobileQuickDecision.parse(response)
            }
            group.addTask { try await Task.sleep(for: timeout); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}
