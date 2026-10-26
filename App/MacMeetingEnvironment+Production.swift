import Foundation
import ListenToMeCore

extension MacMeetingEnvironment {
    static func configured() -> MacMeetingEnvironment {
        MacMeetingEnvironment { store, othersSink, microphoneSink in
            let savedAudioRuns = MacSavedAudio.shared.runs
            let session = MeetingSession(
                store: store,
                context: ContextEngine(debounce: 8),
                makeCapture: {
                    // Only accumulate the Others channel for diarization when the experimental setting
                    // is on — otherwise a normal meeting needlessly resamples + retains up to ~2 h of
                    // audio. Read at capture-creation time so toggling it before the next Listen applies.
                    let diarize = ProviderSettings.speakerDiarizationEnabled
                    // Always reset so a prior run's buffer is released even when the user has since
                    // turned diarization off (otherwise the old ~2 h/~460 MB samples stay resident in
                    // the @State-held sink). The reset also bumps the generation used below.
                    othersSink.reset()
                    microphoneSink.reset()
                    // Capture the generation for THIS run right after the reset above. Any late append
                    // from a prior run's capture carries an older generation and is rejected by the
                    // buffer, so it can't contaminate this run. On the non-diarize path the sink is nil
                    // and the value is unused.
                    let gen = diarize ? othersSink.currentGeneration() : 0
                    let identifyMic = diarize && ProviderSettings.microphoneDiarizationEnabled
                    // Save audio recordings (#55): the conversation was chosen in `beginDiarizationRunReset`.
                    // `MeetingSession.start` makes the capture on the main actor, after placing the recording.
                    let saved = MainActor.assumeIsolated {
                        savedAudioRuns.writersForNewCapture(
                            timesMatchAudio: ProviderSettings.transcriptionEngine != "speechRecognizer")
                    }
                    return DualChannelCapture(othersSink: diarize ? othersSink : nil, sinkGeneration: gen,
                                              microphoneSink: identifyMic ? microphoneSink : nil,
                                              microphoneGeneration: microphoneSink.currentGeneration(),
                                              savedAudio: saved)
                },
                makeTranscriber: {
                    let locale = ProviderSettings.transcriptionLocale()
                    switch ProviderSettings.transcriptionEngine {
                    case "speechRecognizer":
                        return SpeechRecognizerTranscriber(locale: locale) as any Transcribing
                    case "whisperKit":
                        // "Auto" (empty id) → nil locale so WhisperKit auto-detects the language
                        // (enables multilingual / code-switching); an explicit pick forces that language.
                        let whisperLocale = ProviderSettings.transcriptionLocaleID.isEmpty
                            ? nil : ProviderSettings.transcriptionLocale()
                        return WhisperKitTranscriber(locale: whisperLocale, model: ProviderSettings.whisperModel) as any Transcribing
                    default:
                        // Don't warm the system-audio analyzer when this process can't capture system
                        // audio: it would leave an idle analyzer + results task for the whole session
                        // (issue #147). `feed` still builds it lazily if system audio does arrive.
                        return SpeechAnalyzerTranscriber(
                            locale: locale,
                            warmSystemAudio: PermissionsModel.systemAudioLikelyAvailable()
                        ) as any Transcribing
                    }
                },
                makeProvider: { Self.provider(model: $0) },
                models: [
                    .listener: ProviderSettings.model(for: .listener),
                    .quick: ProviderSettings.model(for: .quick),
                    .deep: ProviderSettings.model(for: .deep)
                ],
                providerAvailability: { ProviderSettings.automaticReviewUnavailableReason(quickModel: $0) }
            )
            // Saved audio starts where the starting recording's lines start (#55; #233's recordingOffset).
            savedAudioRuns.timelineOffset = { [weak session] in session?.recordingOffset ?? 0 }
            return session
        }
    }

    /// The provider for `model` on the current AI route; also answers "Ask your history" (#57).
    nonisolated static func provider(model: String) -> any LLMProvider {
        if ProviderSettings.aiMode == .apple { return AppleIntelligenceProvider() as any LLMProvider }
        if ProviderSettings.aiMode == .openAI { return ProviderSettings.openAIProvider(model: model) }
        if ProviderSettings.aiMode == .cloudAI { return ProviderSettings.cloudAIProvider(model: model) }
        return OllamaProvider(model: model, baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey(),
                              localOnly: ProviderSettings.aiMode != .cloud)
    }

    nonisolated static func ollamaKey() -> String? {
        guard ProviderSettings.aiMode == .cloud else { return nil }
        let k = KeychainStore.get("ollama")
        return (k?.isEmpty == false) ? k : nil
    }

    nonisolated static func ollamaBaseURL() -> URL {
        ProviderSettings.aiMode == .cloud
            ? URL(string: "https://ollama.com")!
            : URL(string: "http://localhost:11434")!
    }
}
