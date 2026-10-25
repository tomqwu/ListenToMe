import Foundation
import Observation

@MainActor @Observable
public final class ResponseTimings {
    public enum Outcome: String, Sendable { case requesting, completed, cancelled, failed }
    public struct Measurement: Equatable, Sendable {
        public let startedAt: TimeInterval
        public var firstContent: TimeInterval?
        public var elapsed: TimeInterval?
        public var outcome: Outcome = .requesting
    }
    public private(set) var measurements: [CopilotRole: Measurement] = [:]
    private var sequence = 0
    private var resetFence = 0
    private var current: [CopilotRole: Int] = [:]
    public init() {}
    public func reset() { measurements = [:]; current = [:]; sequence += 1; resetFence = sequence }

    public func clear(_ role: CopilotRole) {
        sequence += 1; current[role] = sequence; measurements[role] = nil
    }

    public func instrument(_ provider: any LLMProvider, role: CopilotRole,
                           clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> any LLMProvider {
        sequence += 1
        let token = sequence
        return TimedProvider(base: provider, clock: clock) { [weak self] measurement in
            await self?.record(measurement, role: role, token: token)
        }
    }

    private func record(_ measurement: Measurement, role: CopilotRole, token: Int) {
        // Old/cancelled streams may finish after a replacement request. Never overwrite its timing.
        guard token > resetFence, token >= (current[role] ?? 0) else { return }
        current[role] = token
        measurements[role] = measurement
    }
}

private struct TimedProvider: LLMProvider {
    let base: any LLMProvider
    let clock: @Sendable () -> TimeInterval
    let update: @Sendable (ResponseTimings.Measurement) async -> Void
    var id: String { base.id }
    var maxPromptCharacters: Int? { base.maxPromptCharacters }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        measured({ base.stream(request) }, hasContent: { !$0.isEmpty })
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        measured({ base.streamEvents(request) }, hasContent: {
            if case .content(let text) = $0 { return !text.isEmpty }
            return false
        })
    }

    private func measured<Value: Sendable>(_ source: @escaping @Sendable () -> AsyncThrowingStream<Value, Error>,
                                           hasContent: @escaping @Sendable (Value) -> Bool) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var result = ResponseTimings.Measurement(startedAt: clock())
                await update(result)
                do {
                    try Task.checkCancellation()
                    for try await event in source() {
                        try Task.checkCancellation()
                        if result.firstContent == nil, hasContent(event) {
                            result.firstContent = max(0, clock() - result.startedAt)
                            await update(result)
                        }
                        continuation.yield(event)
                    }
                    try Task.checkCancellation()
                    result.elapsed = max(0, clock() - result.startedAt); result.outcome = .completed
                    await update(result)
                    continuation.finish()
                } catch {
                    result.elapsed = max(0, clock() - result.startedAt)
                    result.outcome = Task.isCancelled || error is CancellationError ? .cancelled : .failed
                    await update(result)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
