#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// Deterministic UI-test speech updates in isolated storage. Excluded from device/release builds.
struct MobileTranscriptFixture: View {
    @State private var session: MobileSession = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptUI-\(UUID())")
        let session = MobileSession(storageDirectory: root)
        session.title = "Transcript scroll check"
        session.segments = (1...40).map { index in
            TranscriptSegment(source: .you, text: "Point \(index). We reviewed the plan and agreed on the next step.",
                              isFinal: true, start: Double(index), end: Double(index + 1))
        }
        session.partial = TranscriptSegment(source: .you, text: "The latest phrase.",
                                            isFinal: false, start: 41, end: 42)
        session.quickSummary = "## Next steps\n- Review the plan.\n- Confirm the owner.\n- Check progress tomorrow."
        return session
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Grow phrase") {
                    guard let partial = session.partial else { return }
                    let words = String(repeating: " More words arrive while the same phrase is transcribed.", count: 8)
                    session.partial = TranscriptSegment(id: partial.id, source: .you,
                        text: partial.text + words,
                        isFinal: false, start: partial.start, end: partial.end + 1)
                }.accessibilityIdentifier("fixture-grow")
                Button("Finalize") {
                    guard let partial = session.partial else { return }
                    session.segments.append(TranscriptSegment(source: .you, text: partial.text,
                        isFinal: true, start: partial.start, end: partial.end))
                    session.partial = TranscriptSegment(source: .you, text: "A new finalized phrase follows.",
                        isFinal: false, start: partial.end, end: partial.end + 1)
                }.accessibilityIdentifier("fixture-finalize")
            }.font(.caption).buttonStyle(.bordered).dynamicTypeSize(.large)
            MobileMeetingView(session: session)
        }
    }
}
#endif
