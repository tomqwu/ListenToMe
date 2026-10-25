import Foundation
import Observation
import ListenToMeCore

/// Native AI menu state and action use the same current framework query, without changing settings.
@MainActor @Observable
final class MacAIAvailability {
    private(set) var reason: String?
    @ObservationIgnored private let query: () -> String?

    init(query: @escaping () -> String? = { AppleIntelligenceProvider.unavailableReason }) {
        self.query = query
        reason = query()
    }

    var choices: [AIProcessingMode] { MacFeatureReadiness.selectableAIModes(appleReason: reason) }
    func refresh() { reason = query() }

    func select(_ requested: AIProcessingMode, current: AIProcessingMode) -> AIProcessingMode {
        refresh()
        return MacFeatureReadiness.selectAI(requested, current: current, appleReason: reason)
    }
}
