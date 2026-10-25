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
                                    autoInterval: .seconds(2), makeRecorder: { recorder })
        session.title = "Live summary check"
        session.prepareSpeakerModelsIfNeeded()   // as the app does at a foreground launch (#195)
        _recorder = State(initialValue: recorder)
        _session = State(initialValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button("Next test phrase") { recorder.nextPhrase() }.accessibilityIdentifier("nextTestPhrase")
            if ProcessInfo.processInfo.arguments.contains("--review-limit-fixture") {
                Button("Check oversized review") { requestReview(oversized: true) }
                    .accessibilityIdentifier("oversizedReview")
                Button("Shorten review input") { requestReview(oversized: false) }
                    .accessibilityIdentifier("shortenReview")
            }
            MobileMeetingView(session: session)
        }
    }

    private func requestReview(oversized: Bool) {
        session.notes = oversized ? String(repeating: "Reference note. ", count: 4_100) : "Brief note."
        session.automaticReviews.offer([.init(mode: "summary", confidence: "high", reason: "Fixture review")],
                                       source: session.summarySource)
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
    /// No real capture to rebuild in a fixture.
    func reconfigure() async throws {}
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
            let bullets = input.contains("Alex") ? ["**Alex** owns onboarding.", "Review on Thursday."] : ["Review on **Thursday**."]
            // The declared purpose, not the prompt text: the evaluator's system prompt varies with
            // the response-language setting and the data-not-instructions notice (#166).
            // Suggested chips (#61) ride on the same decision; a tapped chip reaches the model literally.
            let suggestions = ["Who owns the Thursday review?", "Draft a reminder for Thursday"]
            if request.purpose == .quickEvaluation,
               let data = try? JSONSerialization.data(withJSONObject: ["reviews": [], "action": "publish",
                   "context": bullets.joined(), "bullets": bullets, "suggestions": suggestions]) {
                continuation.yield(String(decoding: data, as: UTF8.self))
            } else if input.contains(#"The user asks: "Who owns the Thursday review?""#) {
                continuation.yield("Nobody has claimed the Thursday review yet.")
            } else { continuation.yield(bullets.map { "- " + $0 }.joined(separator: "\n")) }
            continuation.finish()
        }
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(request, to: continuation) } }
    }
}
#endif
