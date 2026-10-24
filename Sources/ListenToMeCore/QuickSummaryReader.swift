import Foundation
import Observation

public struct QuickSummaryDecision: Decodable, Sendable {
    public let action: String
    public let context: String
    public let bullets: [String]
    public let reviews: [Review]
    /// Optional suggested prompts (#61), already cleaned by `SuggestedPrompts.sanitize`. Junk entries
    /// are dropped rather than failing the decision: the chips are an extra, the recap is the contract.
    public var suggestions: [String] = []
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
                  acceptedKeys.contains(Set(object.keys)),
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
    /// The envelope's keys. `suggestions` is optional, so models and fixtures that predate it stay valid.
    static let acceptedKeys: [Set<String>] = [["action", "context", "bullets", "reviews"],
                                              ["action", "context", "bullets", "reviews", "suggestions"]]
    private static var invalidResponse: QuickSummaryError { .message("The model did not return a usable Quick Summary update.") }
}

extension QuickSummaryDecision {
    private enum CodingKeys: String, CodingKey { case action, context, bullets, reviews, suggestions }

    /// Decoded by hand so a malformed `suggestions` value costs the chips, never the recap.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        context = try container.decode(String.self, forKey: .context)
        bullets = try container.decode([String].self, forKey: .bullets)
        reviews = try container.decode([Review].self, forKey: .reviews)
        let raw = (try? container.decodeIfPresent([String].self, forKey: .suggestions)) ?? nil
        suggestions = SuggestedPrompts.sanitize(raw ?? [])
    }
}

@MainActor @Observable
public final class QuickSummaryReader {
    /// - Parameter now: seconds on the session's clock; it drives the suggestion refresh window.
    public init(now: @escaping @MainActor () -> TimeInterval = { Date().timeIntervalSince1970 }) { self.now = now }
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    /// The context-aware chips (#61), refreshed by completed evaluations and manual Quick passes.
    public private(set) var suggestions = SuggestedPrompts()
    /// Bumped whenever chips are cleared or the reader is reset. A pass that started under an older provider or model may still
    /// finish (a manual refresh is not cancelled by a settings change); its chips are then dropped.
    public private(set) var providerGeneration = 0
    /// The provider generation the current manual Quick pass started under (`startManualQuick`).
    private var manualPassGeneration: Int?
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
        suggestions = SuggestedPrompts(); providerGeneration += 1
    }

    /// A manual Quick Summary the user asked for is starting: clears the last failure and records the
    /// provider generation its chips will belong to.
    public func startManualQuick() {
        clearError()
        manualPassGeneration = providerGeneration
    }

    /// Offers the suggestions of a pass that ran outside `read`: a manual Quick Summary the user
    /// asked for, which replaces the chips at once. Chips from a pass that started before a provider
    /// or model change are dropped, so an old model's chips never come back.
    public func offerSuggestions(_ candidates: [String]) {
        defer { manualPassGeneration = nil }
        if let started = manualPassGeneration, started != providerGeneration { return }
        suggestions.offer(candidates, at: now(), force: true)
    }

    /// Chips follow the review-suggestion rule: only a read that caught up with the input describes
    /// the whole conversation, so a catch-up read offers none of its own.
    private func offerSuggestions(of decision: QuickSummaryDecision, complete: Bool, provider generation: Int) {
        guard complete, generation == providerGeneration else { return }
        suggestions.offer(decision.suggestions, at: now())
    }

    /// The user tapped a chip: it leaves the row and is not offered again in this conversation.
    public func useSuggestion(_ prompt: String) { suggestions.use(prompt) }

    /// Drops every chip: the provider changed or AI was turned off, so they no longer describe a
    /// pass the current settings would make.
    public func clearSuggestions() { suggestions.clear(); providerGeneration += 1 }

    /// The Quick provider or model changed: its last failure and its chips no longer apply.
    public func providerChanged() { clearError(); clearSuggestions() }

    public func markReviewed(_ mode: String) {
        guard mode != "quick" else { return }
        reviewRevisions[mode, default: 0] += 1
        recommendations.removeAll { $0.mode == mode }
        if !reviewsCompleted.contains(mode) { reviewsCompleted.append(mode) }
    }

    public func clearError() { error = nil; failures = 0 }

    /// See `QuickSummaryContext.relabel`: speaker labels changed, the speech did not.
    public func relabel(from old: [TranscriptSegment], to new: [TranscriptSegment]) {
        context.relabel(from: old, to: new)
    }

    public func read(_ batch: QuickSummaryContext.Batch, provider: any LLMProvider,
              isCurrent: @escaping () -> Bool, apply: @escaping (String) -> Void) async {
        guard task == nil else { return }
        let token = generation
        let providerAtStart = providerGeneration
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
                offerSuggestions(of: decision, complete: !batch.hasMore, provider: providerAtStart)
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
