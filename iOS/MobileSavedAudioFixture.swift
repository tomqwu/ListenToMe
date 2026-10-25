#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// A conversation with saved audio for UI tests (issue #55). The audio is a synthetic tone written by
/// the real writer into isolated storage; nothing is recorded. Excluded from device/release builds.
struct MobileSavedAudioFixture: View {
    @State private var session: MobileSession = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SavedAudioUI-\(UUID())")
        let defaults = UserDefaults(suiteName: "SavedAudioUI-\(UUID())") ?? .standard
        let audio = MobileSavedAudio(root: root.appendingPathComponent("SavedAudio"), defaults: defaults)
        audio.enabled = true
        let session = MobileSession(storageDirectory: root, savedAudio: audio)
        session.title = "Saved audio check"
        session.savedAudioRecognizer = { _, _, language, _ in
            [.init(source: .you, text: "Re-transcribed saved audio example.", isFinal: true,
                   start: 0, end: 2, language: language)]
        }
        session.segments = [0, 3, 6].enumerated().map { index, start in
            TranscriptSegment(source: .you, text: "Line \(index + 1) of the recorded conversation.", isFinal: true,
                              start: start, end: start + 2.5)
        }
        session.save(announce: false)
        if let writer = audio.beginRun(conversation: session.id, offset: 0) {
            let tone = (0..<160_000).map { Float(sin(Double($0) * 0.06) * 0.2) }   // 10 s at 16 kHz
            writer.append(samples: tone, sampleRate: 16_000, timestamp: nil)
            Task { await writer.finish() }   // the part appears once it is closed
        }
        audio.endRun()
        return session
    }()

    var body: some View { MobileMeetingView(session: session) }
}
#endif
