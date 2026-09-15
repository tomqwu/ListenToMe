#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// Only the speech input and model transport are substituted; controls, scheduling and storage are real.
struct MobileIncrementalSummaryFixture: View {
    @State private var recorder: IncrementalFixtureRecorder
    @State private var session: MobileSession

    init() {
        let recorder = IncrementalFixtureRecorder()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IncrementalUI-\(UUID())")
        let slow = ProcessInfo.processInfo.arguments.contains("--incremental-slow-fixture")
        let session = MobileSession(storageDirectory: root, summaryProvider: IncrementalFixtureProvider(slow: slow),
                                    makeRecorder: { recorder })
        session.title = "Delivery discussion"
        session.ai.provider = .ollama
        session.ai.models = [.init(name: "glm-5.3-flash"), .init(name: "glm-5.3")]
        session.ai.quickModel = "glm-5.3-flash"; session.ai.model = "glm-5.3"; session.ai.deepModel = "glm-5.3"
        if ProcessInfo.processInfo.arguments.contains("--incremental-backlog-fixture") {
            session.notes = "We agree delivery on Monday. Sarah will confirm. " + String(repeating: "Background discussion. ", count: 400)
        }
        _recorder = State(initialValue: recorder)
        _session = State(initialValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu("Test speech") {
                    Button("Name topic") { recorder.send("Uh, this is a test for Azure Cloud.") }
                        .accessibilityIdentifier("speechTopic")
                    Button("Ask question") { recorder.send("Help me understand the APM management.") }
                        .accessibilityIdentifier("speechQuestion")
                    Button("Add concern") { recorder.send("QA needs more time before we choose a date.") }
                        .accessibilityIdentifier("speechConcern")
                    Button("Live decision") { recorder.send("We agree delivery on Monday. Sarah will confirm.", final: false) }
                        .accessibilityIdentifier("speechLiveDecision")
                    Button("Agree decision") { recorder.send("We agree delivery on Monday. Sarah will confirm.") }
                        .accessibilityIdentifier("speechDecision")
                    Button("Repeat agreement") { recorder.send("Yes, understood. That is what we agreed.") }
                        .accessibilityIdentifier("speechRepeat")
                    Button("Revise decision") { recorder.send("改到周二交付，Peter负责确认。") }
                        .accessibilityIdentifier("speechRevision")
                    Button("Discuss tradeoff") {
                        recorder.send("Shipping sooner risks data loss; delaying could lose a customer. The tradeoff is unresolved.")
                    }.accessibilityIdentifier("speechTradeoff")
                    Button("Unfinished words") { recorder.send("Maybe we should", final: false) }
                        .accessibilityIdentifier("speechPartial")
                }.accessibilityIdentifier("testSpeechMenu")
                Spacer()
                Text("Checks: \(session.quickReader.completedReads)").font(.caption)
                    .accessibilityIdentifier("quickReadCount")
            }.padding(.horizontal)
            MobileMeetingView(session: session)
        }
    }
}

@MainActor
private final class IncrementalFixtureRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    private var index = 0
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        receive = onSegment
        send("Hello everyone. Good morning.")
    }
    func send(_ text: String, final: Bool = true) {
        receive?(.init(source: .you, text: text, isFinal: final, start: Double(index * 5), end: Double(index * 5 + 4)))
        if final { index += 1 }
    }
    func stop() async throws { receive = nil }
    /// No real capture to rebuild in a fixture.
    func reconfigure() async throws {}
}

private struct IncrementalFixtureProvider: LLMProvider {
    let id = "incremental-ui-fixture"
    let slow: Bool
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: slow ? .seconds(8) : .milliseconds(150))
                    // Match on the request's declared purpose, not on prompt text: the evaluator's
                    // system prompt carries the response-language rule and the data-not-instructions
                    // notice, so an equality check on `instructions` silently stops matching (#166).
                    if request.purpose != .quickEvaluation {
                        // A full review's system prompt is its mode instructions plus the directives
                        // (notice, persona, language) appended by PromptBuilder.systemWithDirectives.
                        let automatic = AutomaticReviewMode.allCases
                            .contains { request.system.hasPrefix($0.instructions) }
                        continuation.yield("- The delivery discussion has been reviewed " + (automatic ? "automatically." : "manually."))
                        continuation.finish()
                        return
                    }
                    let input = try JSONDecoder().decode(MobileQuickContext.Input.self,
                        from: Data((request.messages.first?.content ?? "").utf8))
                    let speech = input.changes.map(\.text).joined(separator: " ")
                    let bullets: [String]
                    if speech.contains("APM") { bullets = ["Discussing Azure Cloud.", "Question: understanding APM management."] }
                    else if speech.contains("Azure") { bullets = ["Discussing Azure Cloud."] }
                    else if speech.contains("周二") { bullets = ["周二交付，Peter负责确认。"] }
                    else if speech.contains("We agree delivery") { bullets = ["Delivery agreed for Monday.", "Sarah will confirm."] }
                    else { bullets = [] }
                    var reviews: [[String: String]] = []
                    if speech.contains("We agree delivery") || speech.contains("周二") || speech.contains("Azure") || speech.contains("APM") {
                        reviews = [["mode": "summary", "confidence": "high", "reason": "The delivery date and owner changed."]]
                    }
                    if speech.contains("tradeoff") || speech.contains("APM") {
                        reviews = [["mode": "deep", "confidence": "high", "reason": "Speed and reliability have an unresolved tradeoff."]]
                    }
                    let body: [String: Any] = ["reviews": reviews, "action": bullets.isEmpty ? "keep" : "publish",
                        "context": String((input.runningContext + " " + speech).suffix(2_000)), "bullets": bullets]
                    continuation.yield(String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
