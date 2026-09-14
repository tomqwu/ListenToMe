import Foundation
import Observation

public struct QuickSummaryDecision: Decodable, Sendable {
    public let action: String
    public let context: String
    public let bullets: [String]
    public let reviews: [Review]
    public struct Review: Codable, Equatable, Sendable {
        public let mode: String
        public let confidence: String
        public let reason: String
        public init(mode: String, confidence: String, reason: String) { self.mode = mode; self.confidence = confidence; self.reason = reason }
    }
    public var summary: String? { action == "publish" ? bullets.map { "- " + $0 }.joined(separator: "\n") : nil }

    public static func parse(_ response: String) throws -> Self {
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
                  result.bullets.count <= 3, result.bullets.joined().count <= 480,
                  result.bullets.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.contains("\n") }),
                  result.action == "keep" ? result.bullets.isEmpty : !result.bullets.isEmpty else { throw invalidResponse }
            return result
        }
        throw invalidResponse
    }
    private static var invalidResponse: QuickSummaryError { .message("The model did not return a usable Quick Summary update.") }
}

@MainActor @Observable
public final class QuickSummaryReader {
    public init() {}
    public private(set) var context = QuickSummaryContext()
    public private(set) var isReading = false
    public private(set) var error: String?
    public private(set) var unchanged = false
    public private(set) var completedReads = 0
    public private(set) var failures = 0
    public private(set) var recommendations: [QuickSummaryDecision.Review] = []
    public private(set) var reviewsCompleted: [String] = []
    private var reviewRevisions: [String: Int] = [:]
    public private(set) var isCatchingUp = false
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public func cancel() {
        generation = UUID()
        task?.cancel(); task = nil; isReading = false
    }

    public func reset() {
        cancel(); context = QuickSummaryContext(); error = nil; unchanged = false; completedReads = 0; failures = 0
        recommendations = []; reviewsCompleted = []; reviewRevisions = [:]; isCatchingUp = false
    }

    public func markReviewed(_ mode: String) {
        guard mode != "quick" else { return }
        reviewRevisions[mode, default: 0] += 1
        recommendations.removeAll { $0.mode == mode }
        if !reviewsCompleted.contains(mode) { reviewsCompleted.append(mode) }
    }

    public func clearError() { error = nil; failures = 0 }

    public func read(_ batch: QuickSummaryContext.Batch, provider: any LLMProvider,
              isCurrent: @escaping () -> Bool, apply: @escaping (String) -> Void) async {
        guard task == nil else { return }
        let token = generation
        let completedBeforeRead = reviewsCompleted
        let revisionsBeforeRead = reviewRevisions
        isReading = true
        task = Task {
            defer { if generation == token { isReading = false; task = nil } }
            do {
                let decision = try await Self.evaluate(batch.request, provider: provider)
                try Task.checkCancellation()
                guard generation == token, isCurrent() else { return }
                context.accept(batch, memory: decision.context)
                isCatchingUp = batch.hasMore
                error = nil; failures = 0; completedReads += 1
                // A manual review may finish during this evaluation. Do not resurrect its stale suggestion.
                let completedDuringRead = Set(reviewRevisions.keys.filter { reviewRevisions[$0] != revisionsBeforeRead[$0] })
                recommendations = []
                for action in LiveSummaryScheduler.actions(for: decision) {
                    switch action {
                    case .keepQuick:
                        unchanged = true
                    case .publishQuick(let output):
                        unchanged = false
                        apply(output)
                    case .suggestReview(let review):
                        if !batch.hasMore, !completedDuringRead.contains(review.mode) { recommendations.append(review) }
                    }
                }
                reviewsCompleted.removeAll { completedBeforeRead.contains($0) && !completedDuringRead.contains($0) }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                failures += 1
                self.error = "Quick Summary check failed: \(Self.failureMessage(error)) Your previous summary is kept."
            }
        }
        await task?.value
    }

    private static func failureMessage(_ error: Error) -> String {
        if let network = error as? URLError {
            switch network.code {
            case .networkConnectionLost: return "The internet connection was lost."
            case .notConnectedToInternet: return "This device is offline. Connect to the internet to continue."
            case .timedOut: return "The request timed out. Try again when the connection improves."
            default: break
            }
        }
        return error.localizedDescription
    }

    public static func evaluate(_ request: LLMRequest, provider: any LLMProvider,
                         timeout: Duration = .seconds(30)) async throws -> QuickSummaryDecision {
        try await withThrowingTaskGroup(of: QuickSummaryDecision.self) { group in
            group.addTask {
                var response = ""
                for try await delta in provider.stream(request) {
                    try Task.checkCancellation()
                    response += delta
                    guard response.utf8.count <= 16_384 else { throw QuickSummaryError.message("Quick Summary response was too large.") }
                }
                try Task.checkCancellation()
                return try QuickSummaryDecision.parse(response)
            }
            group.addTask { try await Task.sleep(for: timeout); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

/// Tracks a manual Quick answer the user asked for (Draft reply, Key terms, Counterpoint…) so the
/// automatic recap cannot replace it while they are still reading it. The automatic recap is kept
/// separately and stays the evaluator's `visibleSummary`; only the *displayed* value is held back.
public struct ManualQuickAnswer: Sendable {
    /// How long a completed manual answer keeps the Quick pane. Requesting another answer, clearing
    /// the conversation or dismissing the answer ends it sooner. Once it elapses the pane follows the
    /// recap again on the next automatic apply; the answer stays reachable until then, and "Show
    /// recap" stays available the whole time, so an expired answer can never strand a newer recap.
    public static let freshness: TimeInterval = 120
    /// Seconds on the session's injected clock, so expiry is testable without waiting.
    private var completedAt: TimeInterval?
    public init() {}
    /// A manual answer finished streaming and is now on screen.
    public mutating func completed(at now: TimeInterval) { completedAt = now }
    /// The user dismissed the answer, started a new request, or the conversation was reset.
    public mutating func dismiss() { completedAt = nil }
    public func isFresh(at now: TimeInterval) -> Bool {
        guard let completedAt else { return false }
        return now - completedAt < Self.freshness
    }
}

public enum QuickSummaryError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): return message } }
}
