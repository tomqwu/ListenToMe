import Foundation

extension MeetingSession {
    public func setTranslationSuspended(_ suspended: Bool) {
        liveTranslation.setSuspended(suspended)
        summaryTranslation.worker.setSuspended(suspended)
    }
    /// Derived translations follow finalized original lines; audio capture never waits for this work.
    public func updateLiveTranslations() {
        liveTranslation.update(conversationID: translationContextID, segments: store.utterances,
                               fallbackLanguage: nil, options: languageOptions)
    }
    public func updateSummaryTranslation() {
        summaryTranslation.update(source: listenerSummary, conversationID: translationContextID,
            target: languageOptions.summaryTranslationTarget, isGenerating: streamingRoles.contains(.listener))
    }
}
