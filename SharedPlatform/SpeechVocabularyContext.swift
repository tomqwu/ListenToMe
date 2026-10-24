import Speech

/// Hands the active vocabularies to Apple's speech analyzer (issue #222), on iOS and macOS.
///
/// Verified against the iOS 26 / macOS 26 SDK (Speech.swiftinterface): `AnalysisContext.contextualStrings`
/// is a `[ContextualStringsTag: [String]]` dictionary, and `SpeechAnalyzer.setContext(_:)` replaces a
/// running analyzer's context, so a vocabulary added mid-recording applies without restarting capture.
/// Apple's documentation asks for short phrases and no more than 100 in total, which
/// `ActiveVocabulary.recognitionTerms` enforces. The documentation describes the effect for
/// `DictationTranscriber`; how much it biases `SpeechTranscriber` is measured on a device (see
/// docs/manual-smoke-test.md), not assumed.
enum SpeechVocabularyContext {
    static func context(_ strings: [String]) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings = strings.isEmpty ? [:] : [.general: strings]
        return context
    }

    /// Replaces the analyzer's contextual strings. A failure leaves recognition running without them,
    /// which is how it ran before vocabularies existed, so it is not reported as an error.
    static func apply(_ strings: [String], to analyzer: SpeechAnalyzer) async {
        try? await analyzer.setContext(context(strings))
    }
}
