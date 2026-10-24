import Foundation
import ListenToMeCore

/// Where the active vocabularies reach recognition, correction and summaries (issue #222).
extension MobileSession {
    /// While recording use the recognizer's language; a reopened conversation uses its saved current
    /// language, rather than the Settings choice for a future recording.
    var vocabularyLanguage: String {
        if state != .idle { return recordingLanguage }
        return languageDetection.languageChanges[id]?.last
            ?? history.first(where: { $0.id == id })?.conversationLanguages.current
            ?? conversationLanguage
    }

    /// The vocabularies in effect for the open conversation.
    var activeVocabulary: ActiveVocabulary { vocabulary.active(for: id, localeIdentifier: vocabularyLanguage) }

    /// Contextual strings for the recognizer, capped by `ActiveVocabulary.recognitionTerms`; My terms
    /// already said in this conversation, then the newest, are kept first.
    var vocabularyRecognitionTerms: [String] {
        vocabulary.recognitionTerms(for: id, heard: segments.suffix(200).map(\.text).joined(separator: " "),
                                    localeIdentifier: state == .idle ? vocabularyLanguage : recordingLanguage)
    }

    /// Session context for a manual Summary or Quick request: the domain, a glossary favoring
    /// terms heard recently, and (Summary only) the domain's headings. The on-device Apple model gets a
    /// smaller share, which `summarize` also charges against its transcript cap.
    /// `heard` ranks the glossary by other text than the latest conversation, such as the lines a
    /// selection summary sends (#234).
    func vocabularyGuidance(for mode: MobileSummaryMode, cloud: Bool, heard: String? = nil) -> String? {
        let window = cloud ? nil : PromptBudget.appleIntelligenceCharacters
        return VocabularyPrompt.combined(persona: ConversationPrompt.guidance(summaryInstructions), guidance: VocabularyPrompt.guidance(
            for: activeVocabulary, transcript: String((heard ?? summarySource).suffix(4_000)),
            characterLimit: VocabularyPrompt.characterLimit(forPromptWindow: window), includeLayout: mode == .summary))
    }

    /// Automatic Summary reviews carry the same context, with the domain's headings, through their
    /// directives (iOS runs no Deep, #235).
    var vocabularyDirectives: AutomaticReviewDirectives {
        AutomaticReviewDirectives(personaGuidance: VocabularyPrompt.combined(persona: ConversationPrompt.guidance(summaryInstructions),
            guidance: VocabularyPrompt.guidance(for: activeVocabulary)),
                                  summaryGuidance: VocabularyPrompt.layoutInstruction(for: activeVocabulary))
    }

    /// Hands the current terms to the running recorder, which applies them without restarting capture.
    func applyVocabularyToRecording() {
        guard let recorder else { return }
        let terms = vocabularyRecognitionTerms
        Task { await recorder.setContextualStrings(terms) }
    }

    /// Counts a finalized line toward the on-device suggestion check.
    func considerVocabularySuggestion(_ segment: TranscriptSegment) {
        vocabulary.heard(segment.text, conversationID: id, localeIdentifier: segment.language ?? recordingLanguage,
                         recent: self.segments.suffix(200).map(\.text).joined(separator: " "))
    }

    /// The banner's "Add": the preset is on for this conversation, at once.
    func addSuggestedVocabulary() {
        vocabulary.addSuggested()
        applyVocabularyToRecording()
    }

    func useSuggestedVocabularyByDefault() {
        vocabulary.useSuggestedByDefault()
        applyVocabularyToRecording()
    }

    /// "Add to My terms" from a transcript line; returns why it was not added, or nil.
    @discardableResult
    func addToMyTerms(_ term: String) -> String? {
        let problem = vocabulary.addTerm(term)
        if problem == nil { applyVocabularyToRecording() }
        return problem
    }

    /// The glossary the correction prompt receives for one phrase.
    func correctionGlossary(for text: String) -> [String] {
        vocabulary.correctionLookup(for: id, localeIdentifier: vocabularyLanguage).glossary(for: text)
    }
}
