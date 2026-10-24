import Foundation
import ListenToMeCore

/// Where "Ask your history" (issue #57) sends a question on the Mac: the current AI route, with the
/// Deep pane's model. AI off never asks; local Ollama (verified local) and Apple Intelligence
/// answer on this Mac; every other route is named in the disclosure before anything is sent.
extension MeetingView {
    @MainActor static func historyAskRoute() -> HistoryAskRoute {
        let mode = ProviderSettings.aiMode
        if mode == .off { return .unavailable("AI is off. Choose an AI mode in Settings to ask your history.") }
        if mode == .apple, let reason = AppleIntelligenceProvider.unavailableReason { return .unavailable(reason) }
        let model = ProviderSettings.model(for: .deep)
        if mode != .apple && model.isEmpty {
            return .unavailable("Choose a model for the Deep pane to ask your history.")
        }
        let label = mode == .cloud ? "Ollama Cloud" : ProviderSettings.aiModeLabel
        return HistoryAskRoute(unavailable: nil, destination: HistoryQuestion.destination(for: mode, label: label),
                               responseLanguage: ProviderSettings.responseLanguageDirective(),
                               makeProvider: { provider(model: model) })
    }
}
