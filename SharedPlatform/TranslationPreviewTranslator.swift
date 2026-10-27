#if DEBUG
import Foundation
import ListenToMeCore

/// Explicit UI-test/preview metadata and synthetic responses. Never compiled into release builds;
/// production uses AppleTranscriptTranslator and separate real-model acceptance.
@MainActor final class TranslationPreviewTranslator: TranscriptTranslating {
    let needsPacks: Bool
    init(needsPacks: Bool = false) { self.needsPacks = needsPacks }
    func sourceLanguage(for text: String, hint: String?) -> String? { "en" }
    func availability(source: String, target: String) async -> FeatureAvailability {
        needsPacks ? .setupRequired(reason: "Download the selected translation languages on this device first.",
                                   action: "Prepare languages") : .ready
    }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        let summaries = [
            "Decisions": "Décisions", "Next steps": "Prochaines étapes",
            "The first release will focus on the essential experience. Extra features will wait for user feedback.":
                "La première version se concentrera sur l’essentiel. Les fonctions supplémentaires attendront les retours.",
            "Alex will prepare the onboarding flow.": "Alex préparera l’accueil.",
            "The team will review the prototype on Thursday.": "L’équipe examinera le prototype jeudi.",
            "Collect feedback before expanding the scope.": "Recueillir les retours avant d’élargir le périmètre."
        ]
        if let value = summaries[text] { return value }
        return text.contains("Alex") ? "Alex préparera l’accueil; nous recueillerons les retours."
            : "La première version se concentre sur l’essentiel; revue du prototype jeudi."
    }
    func cancel() {}
}
#endif
