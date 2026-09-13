import Foundation

/// Pure event-to-action policy. It never calls a model, records speech, or mutates a summary.
public struct LiveSummaryScheduler {
    public enum Event {
        case transcriptChanged, notesChanged, recordingChanged, automationChanged, providerChanged
        case timerFired, evaluationFinished, manualQuickStarted, manualQuickFinished, conversationChanged
    }
    public enum Action: Equatable {
        case cancelWake, cancelEvaluation, schedule(Duration), evaluate
    }
    public enum EvaluationAction: Equatable {
        case keepQuick
        case publishQuick(String)
        case suggestReview(QuickSummaryDecision.Review)
    }

    public static func actions(for evaluation: QuickSummaryDecision) -> [EvaluationAction] {
        var actions: [EvaluationAction] = [evaluation.summary.map { .publishQuick($0) } ?? .keepQuick]
        actions += evaluation.reviews.map { .suggestReview($0) }
        return actions
    }

    public struct Snapshot {
        public var recording: Bool
        public var automatic: Bool
        public var pending: Bool
        public var reading: Bool
        public var manualQuick: Bool
        public var available: Bool
        public var correctingSpeech: Bool = false
        public var failures: Int = 0
        public init(recording: Bool, automatic: Bool, pending: Bool, reading: Bool, manualQuick: Bool,
                    available: Bool, correctingSpeech: Bool = false, failures: Int = 0) {
            self.recording = recording; self.automatic = automatic; self.pending = pending
            self.reading = reading; self.manualQuick = manualQuick; self.available = available
            self.correctingSpeech = correctingSpeech; self.failures = failures
        }
    }
    public let interval: Duration
    private var firstPending: ContinuousClock.Instant?
    private var lastAttempt: ContinuousClock.Instant?
    private var evaluationPlanned = false

    public init(interval: Duration = .seconds(5)) { self.interval = interval }

    public mutating func plan(_ event: Event, state: Snapshot, now: ContinuousClock.Instant = .now) -> [Action] {
        var actions: [Action] = [.cancelWake]
        switch event {
        case .evaluationFinished: evaluationPlanned = false
        case .conversationChanged, .providerChanged:
            firstPending = nil; lastAttempt = nil; evaluationPlanned = false
            actions.append(.cancelEvaluation)
        case .manualQuickStarted:
            evaluationPlanned = false
            return [.cancelWake, .cancelEvaluation]
        default: break
        }
        guard state.recording, state.automatic else {
            firstPending = nil; evaluationPlanned = false
            return [.cancelWake, .cancelEvaluation]
        }
        guard state.pending else { firstPending = nil; return actions }
        guard state.available, !state.manualQuick, !evaluationPlanned,
              !state.reading || event == .providerChanged else { return actions }
        if firstPending == nil { firstPending = now }
        let cooldown = min(.seconds(60), interval * (1 << min(state.failures, 4)))
        let base = lastAttempt ?? firstPending ?? now
        // The grace is bounded relative to this batch's deadline, so continuous correction cannot starve Quick.
        let deadline = base + cooldown + (state.correctingSpeech ? .seconds(2) : .zero)
        if event == .timerFired, now >= deadline {
            lastAttempt = now; firstPending = nil; evaluationPlanned = true
            actions.append(.evaluate)
        } else {
            actions.append(.schedule(max(.milliseconds(1), deadline - now)))
        }
        return actions
    }
}
