#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// A saved conversation with labeled lines and a synthetic model, for Select mode and selection
/// summaries (issue #234). No model download, microphone or network.
///
/// `--selection-summary-fixture` answers on "this device" (the on-device path, faked);
/// `--selection-server` routes it through the chosen server instead, to show the disclosure;
/// `--selection-unavailable` leaves no usable provider, so Summarize selection says why.
struct MobileSelectionSummaryFixture: View {
    @State private var session: MobileSession = {
        let arguments = ProcessInfo.processInfo.arguments
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelectionUI-\(UUID())")
        let provider = SelectionFixtureProvider()
        let server = arguments.contains("--selection-server")
        let session = MobileSession(storageDirectory: root, summaryProvider: server ? provider : nil)
        session.ai.provider = arguments.contains("--selection-unavailable") || server ? .ollama : .apple
        if !server && !arguments.contains("--selection-unavailable") { session.onDeviceProviderOverride = provider }
        session.title = "Launch review"
        session.segments = [
            TranscriptSegment(source: .you, text: "Good morning, everyone.", isFinal: true, start: 0, end: 3,
                              speakerName: "Speaker 1"),
            TranscriptSegment(source: .you, text: "We ship the beta on Friday.", isFinal: true, start: 62, end: 66,
                              speakerName: "Alex"),
            TranscriptSegment(source: .you, text: "QA signs off on Thursday.", isFinal: true, start: 70, end: 75,
                              speakerName: "Sam"),
            TranscriptSegment(source: .you, text: "Marketing waits for the sign-off.", isFinal: true, start: 80, end: 85,
                              speakerName: "Alex")
        ]
        session.save(announce: false)
        return session
    }()

    var body: some View { MobileMeetingView(session: session) }
}

/// Echoes which selected lines it was given, so a test can see exactly what was sent.
private struct SelectionFixtureProvider: LLMProvider {
    let id = "selection-ui-fixture"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let user = request.messages.first?.content ?? ""
            let lines = user.split(separator: "\n").filter { $0.hasPrefix("[") }
            continuation.yield("- Summary of \(lines.count) selected line\(lines.count == 1 ? "" : "s").\n")
            if let first = lines.first { continuation.yield("- Starts with: \(first)") }
            continuation.finish()
        }
    }
}
#endif
