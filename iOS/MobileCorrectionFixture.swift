#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

struct MobileCorrectionFixture: View {
    @State private var session: MobileSession
    @State private var recorder: CorrectionFixtureRecorder

    init() {
        let recorder = CorrectionFixtureRecorder()
        _recorder = State(initialValue: recorder)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorrectionUI-\(UUID())")
        let session = MobileSession(storageDirectory: root, correctionProvider: CorrectionFixtureProvider(),
                                    makeRecorder: { recorder })
        let savedCatalog = UserDefaults.standard.object(forKey: "mobileOllamaCatalog")
        let savedModel = UserDefaults.standard.object(forKey: "mobileCorrectionModel")
        session.ai.models = [.init(name: "glm-test-flash"), .init(name: "qwen-test-flash"), .init(name: "glm-test-pro")]
        session.ai.correctionModel = "glm-test-flash"
        UserDefaults.standard.set(savedCatalog, forKey: "mobileOllamaCatalog")
        UserDefaults.standard.set(savedModel, forKey: "mobileCorrectionModel")
        session.title = "Meeting notes"
        _session = State(initialValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button("Test phrase") { recorder.sendPhrase() }.accessibilityIdentifier("correctionTestPhrase")
            MobileMeetingView(session: session)
        }
    }
}

@MainActor
private final class CorrectionFixtureRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        receive = onSegment
        onSegment(.init(source: .you, text: "We are discussing meeting notes.", isFinal: true, start: 0, end: 1))
    }
    func sendPhrase() {
        receive?(.init(source: .you, text: "Please send the meeting goats to Alex.", isFinal: true, start: 1, end: 3))
    }
    func stop() async throws { receive = nil }
    /// No real capture to rebuild in a fixture.
    func reconfigure() async throws {}
}

private struct CorrectionFixtureProvider: LLMProvider {
    let id = "correction-ui-fixture"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let payload = try? JSONDecoder().decode([String: String].self, from: Data((request.messages.first?.content ?? "").utf8))
            let text = (payload?["text"] ?? "").replacingOccurrences(of: "goats", with: "notes")
            if let data = try? JSONEncoder().encode(["text": text]) { continuation.yield(String(decoding: data, as: UTF8.self)) }
            continuation.finish()
        }
    }
}
#endif
