#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// Synthetic content for reviewing the real screens, without test controls or cloud requests.
struct MobileDesignFixture: View {
    @State private var session: MobileSession = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DesignUI-\(UUID())")
        // Synthetic release visuals explicitly represent a compatible recording device.
        // The ordinary simulator app keeps its actual unavailable capture status.
        let answer = """
        ## A focused first release
        - Keep the scope small and useful.
        - **Alex** owns onboarding.
        - Review the prototype on **Thursday**.
        """
        let session = MobileSession(storageDirectory: root,
                                    summaryProvider: PreviewProvider(answer: answer),
                                    sharedInbox: root.appendingPathComponent("SharedInbox"),
                                    watchInbox: WatchInbox(root: root.appendingPathComponent("WatchInbox")),
                                    makeRecorder: { PreviewRecorder() }, makeDiarizer: { PreviewDiarizer() },
                                    recordingSupport: { _ in .ready })
        if ProcessInfo.processInfo.arguments.contains("--translation-fixture") {
            let translator = TranslationPreviewTranslator(
                needsPacks: ProcessInfo.processInfo.arguments.contains("--translation-needs-packs"))
            session.liveTranslation.translator = translator
            session.summaryTranslation.worker.translator = translator
        }
        session.title = "Product planning"
        session.segments = [
            TranscriptSegment(source: .you,
                              text: "Let's keep the first release focused on the essentials. " +
                                  "We can review the prototype on Thursday.",
                              isFinal: true, start: 0, end: 12),
            TranscriptSegment(source: .you,
                              text: "Alex will own the onboarding flow. " +
                                  "We'll collect feedback before adding more features.",
                              isFinal: true, start: 12, end: 25)
        ]
        session.quickSummary = answer
        session.summary = """
        ## Decisions
        The first release will focus on the essential experience. Extra features will wait for user feedback.

        ## Next steps
        - Alex will prepare the onboarding flow.
        - The team will review the prototype on Thursday.
        - Collect feedback before expanding the scope.
        """
        // Deep analysis an older version saved with this conversation; read-only on iOS (#235).
        session.earlierDeepAnalysis = """
        ## The direction
        A smaller first release gives the team room to learn from real use before making a bigger investment.

        ## Watch closely
        The onboarding flow is the first test of whether the core experience is clear.
        Agree on what success looks like before Thursday's review.

        ## Open question
        Which feedback would change the scope of the next release?
        """
        session.notes = "Thursday prototype review\n\nAlex — onboarding\nBring feedback and open questions."
        session.save(announce: false)
        return session
    }()

    var body: some View { MobileMeetingView(session: session).mobileSessionLifecycle(session) }
}
#endif
