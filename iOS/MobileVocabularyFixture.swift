#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// UI-test fixture for domain vocabularies (issue #222): a recorder that speaks a short medical
/// consultation on demand and shows the contextual strings the recognizer would have received.
struct MobileVocabularyFixture: View {
    @State private var session: MobileSession
    @State private var recorder: VocabularyFixtureRecorder

    init() {
        UserDefaults.standard.removeObject(forKey: VocabularySettingsStore.key)
        let recorder = VocabularyFixtureRecorder()
        _recorder = State(initialValue: recorder)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VocabularyUI-\(UUID())")
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        session.prepareSpeakerModelsIfNeeded()
        session.title = "Clinic follow-up"
        _session = State(initialValue: session)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Speak") { recorder.speak() }.accessibilityIdentifier("vocabularySpeak")
                Text(recorder.summary).font(.caption2).accessibilityIdentifier("vocabularyRecognizerTerms")
            }
            MobileMeetingView(session: session)
        }
    }
}

@MainActor @Observable
private final class VocabularyFixtureRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    private var terms: [String] = []
    private var time = 0.0
    var summary = "recognizer: 0"

    func setContextualStrings(_ strings: [String]) async {
        terms = strings
        summary = "recognizer: \(strings.count)" + (strings.first.map { " · first: \($0)" } ?? "")
            + (strings.contains("metoprolol") ? " · medical" : "")
    }

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { receive = onSegment }

    func speak() {
        for line in Self.consultation {
            receive?(.init(source: .you, text: line, isFinal: true, start: time, end: time + 4))
            time += 4
        }
    }

    func stop() async throws { receive = nil }
    func reconfigure() async throws {}

    private static let consultation = [
        "okay so this is a sixty eight year old woman with a history of atrial fibrillation and heart failure",
        "she came in with worsening dyspnea over the last week and can't lie flat anymore",
        "she's on apixaban five milligrams BID, metoprolol twenty five twice a day, and furosemide forty daily",
        "on exam she has pitting edema up to the knees and crackles at both bases",
        "troponin was flat times two and BNP is elevated at around eleven hundred",
        "her creatinine bumped from one point one to one point six so i'm a little worried about her kidneys",
        "can we get an echocardiogram today, her last ejection fraction was thirty five percent a year ago",
        "let's switch the furosemide to forty IV twice a day and keep her on a fluid restriction",
        "strict ins and outs, daily weights, and recheck labs in the morning, no allergies listed in the chart",
        "please loop in Okafor about the Kubeflow results before the family meeting this afternoon"
    ]
}
#endif
