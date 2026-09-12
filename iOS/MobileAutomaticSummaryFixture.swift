#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// Drives the real Start/Stop path with synthetic speech; never requests microphone or cloud access.
struct MobileAutomaticSummaryFixture: View {
    @State private var recorder: FixtureRecorder
    @State private var session: MobileSession

    init() {
        let recorder = FixtureRecorder()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AutoUI-\(UUID())")
        let failFirst = ProcessInfo.processInfo.arguments.contains("--automatic-failure-fixture")
        let session = MobileSession(storageDirectory: root, summaryProvider: FixtureSummaryProvider(failFirst: failFirst),
                                    autoInterval: .seconds(failFirst ? 6 : 2), makeRecorder: { recorder })
        session.title = "Live summary check"
        _recorder = State(initialValue: recorder)
        _session = State(initialValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button("Next test phrase") { recorder.nextPhrase() }.accessibilityIdentifier("nextTestPhrase")
            MobileMeetingView(session: session)
        }
    }
}

@MainActor
private final class FixtureRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        receive = onSegment
        onSegment(TranscriptSegment(source: .you, text: "Review the prototype on Thursday.", isFinal: true, start: 0, end: 3))
    }
    func nextPhrase() {
        receive?(TranscriptSegment(source: .you, text: "Alex owns onboarding.", isFinal: true, start: 3, end: 6))
    }
    func stop() async throws { receive = nil }
}

private actor FixtureSummaryProvider: LLMProvider {
    nonisolated let id = "automatic-ui-fixture"
    private var failFirst: Bool
    init(failFirst: Bool) { self.failFirst = failFirst }
    private func respond(_ request: LLMRequest, to continuation: AsyncThrowingStream<String, Error>.Continuation) {
        if failFirst {
            failFirst = false
            continuation.finish(throwing: URLError(.networkConnectionLost))
        } else {
            let input = request.messages.last?.content ?? ""
            continuation.yield(input.contains("Alex") ? "- **Alex** owns onboarding.\n- Review on Thursday." : "- Review on **Thursday**.")
            continuation.finish()
        }
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(request, to: continuation) } }
    }
}
#endif
