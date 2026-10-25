#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// The real periodic activity loop with synthetic audio and no recognition results or model download.
struct MobileLanguageActivityFixture: View {
    @State private var session: MobileSession = {
        let recorder = ActivityFixtureRecorder()
        let session = MobileSession(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LanguageActivityUI-\(UUID())"), makeRecorder: { recorder },
            makeLanguageModel: { ActivityFixtureModel() })
        session.languageChoice = MobileSession.automaticLanguageTag
        session.title = "Automatic language check"
        return session
    }()

    var body: some View {
        MobileMeetingView(session: session)
            .safeAreaInset(edge: .top) {
                Text("Recognized results: \(session.speechEventCount)")
                    .font(.caption).accessibilityIdentifier("activityFixtureResults")
            }
    }
}

@MainActor
private final class ActivityFixtureRecorder: MobileRecording {
    private var buffer: SpeakerAudioBuffer?
    func attachLanguageAudio(_ buffer: SpeakerAudioBuffer?) { self.buffer = buffer }
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        guard let buffer else { return }
        buffer.append(samples: Array(repeating: 0.1, count: 12 * 16_000), sampleRate: 16_000,
                      timestamp: 0, generation: buffer.currentGeneration())
    }
    func stop() async throws {}
    func reconfigure() async throws {}
    func switchLocale(to locale: Locale, replay: SpeakerAudioBuffer?, replayFrom: @MainActor () -> Int?,
                      willReplace: @escaping @MainActor (Bool, TimeInterval) -> Void) async throws {
        willReplace(true, 12)
    }
}

private actor ActivityFixtureModel: MobileLanguageIdentifying {
    func prepare() async throws {}
    func detect(samples: [Float]) async throws -> LanguageGuess { LanguageGuess(language: "zh", probability: 0.99) }
    func supportedLocales() async -> [String] { ["en-US", "zh-CN"] }
}
#endif
