import SwiftUI
import ListenToMeCore

extension MobileSession {
    func updateSummaryTranslation() {
        summaryTranslation.update(source: summary, conversationID: id, target: languageOptions.summaryTranslationTarget,
                                  isGenerating: generatingMode == .summary)
    }
    func updateLiveTranslations() {
        liveTranslation.update(conversationID: id, segments: segments, fallbackLanguage: nil, options: languageOptions)
    }
}

struct MobileLanguageOptionsView: View {
    @Bindable var session: MobileSession
    var body: some View {
        Form {
            ConversationLanguageControls(options: $session.languageOptions,
                translation: session.liveTranslation, conversationID: session.id,
                save: { session.save(announce: false) })
        }.navigationTitle("Live translation")
    }
}
