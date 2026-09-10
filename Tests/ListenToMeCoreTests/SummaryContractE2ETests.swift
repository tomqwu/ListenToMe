import XCTest
@testable import ListenToMeCore

/// Explicit opt-in: a synthetic hour of transcript through the actual local-only provider.
/// This validates AI context/summary fidelity, not a one-hour audio stability soak.
@MainActor
final class SummaryContractE2ETests: XCTestCase {
    func testEarlyMiddleAndLateActionsSurviveRealModelSummary() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LTM_SUMMARY_E2E"] == "1", "explicit local model summary fixture only")
        let model = env["LTM_E2E_MODEL"] ?? "llama3.1"
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
                                     makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                                     makeProvider: { OllamaProvider(model: $0, localOnly: true) },
                                     models: [.listener: model])
        let actions = [0: "Decision: this is a pilot release. Alice will prepare the rollout checklist by Wednesday.",
                       30: "Decision: postpone the budget review. Bob will send cost numbers by Thursday.",
                       59: "Dana will review the rollback procedure by Friday. No other commitments were made."]
        for minute in 0..<60 {
            let text = actions[minute] ?? String(repeating:
                "Routine progress check. We are discussing the same pilot. No change to earlier decisions or actions. ",
                count: 6)
            session.store.apply(TranscriptSegment(source: .others, text: "Minute \(minute): " + text,
                                                   isFinal: true, start: Double(minute * 60), end: Double(minute * 60 + 55)))
        }
        await session.refreshListener()
        let summary = session.listenerSummary
        print("SYNTHETIC SUMMARY RESULT:\n\(summary)\nEND SYNTHETIC SUMMARY")
        XCTAssertFalse(summary.contains("⚠️"), summary)
        for fact in ["Alice", "Wednesday", "Bob", "Thursday", "Dana", "Friday", "pilot", "budget"] {
            XCTAssertTrue(summary.localizedCaseInsensitiveContains(fact), "Missing \(fact): \(summary)")
        }
    }
}
