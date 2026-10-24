import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #235: iOS keeps Quick and Summary. The evaluator may still recommend Deep (its prompt is
/// shared with macOS); iOS ignores it. A Deep analysis an older version saved is kept, read-only.
@MainActor
final class MobileNoDeepTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testAutoIgnoresTheEvaluatorsDeepRecommendation() async throws {
        let provider = DeepRecommendingProvider()
        let recorder = NoDeepRecorder()
        let session = MobileSession(storageDirectory: root, summaryProvider: provider,
                                    autoInterval: .milliseconds(50), makeRecorder: { recorder })
        let originalAuto = session.autoQuick, originalCorrection = session.ai.correctTranscript
        defer { session.state = .idle; session.autoQuick = originalAuto; session.ai.correctTranscript = originalCorrection }
        session.ai.correctTranscript = false
        session.autoQuick = true
        session.start()
        try await waitUntil { (session.automaticReviews.completedCounts[.summary] ?? 0) == 1 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(session.summary, "Summary review")
        XCTAssertNil(session.automaticReviews.completedCounts[.deep])
        XCTAssertEqual(session.automaticReviews.modes, [.summary])
        XCTAssertTrue(session.earlierDeepAnalysis.isEmpty, "Nothing new is generated as Deep")
        let reviews = await provider.reviewSystems()
        XCTAssertEqual(reviews.count, 1, "Only the Summary review reaches the model")
        XCTAssertTrue(reviews.allSatisfy { $0.hasPrefix(AutomaticReviewMode.summary.instructions) })
        await session.stop()
    }

    func testAnEarlierDeepAnalysisSurvivesOpeningEditingAndSaving() throws {
        let session = MobileSession(storageDirectory: root)
        let record = SessionRecord(id: "older", title: "Older meeting", date: Date(), transcript: "", summary: "Recap",
                                   segments: [], notes: "Notes", quickSuggestion: "- Quick",
                                   deepAnswer: "## Tradeoffs\nShip later.")
        session.open(record)
        XCTAssertEqual(session.earlierDeepAnalysis, "## Tradeoffs\nShip later.")
        XCTAssertEqual(MobileSummaryMode.allCases, [.summary, .quick], "No Deep pane to write it")
        session.notes += " More."
        XCTAssertTrue(session.save())
        let saved = try XCTUnwrap(session.history.first { $0.id == "older" })
        XCTAssertEqual(saved.deepAnswer, "## Tradeoffs\nShip later.", "Kept with the record")
        XCTAssertTrue(MobileSession.markdown(for: saved).contains("Ship later."), "Kept in exports and notes")
        XCTAssertTrue(session.markdown.contains("Ship later."))
        session.newConversation()
        XCTAssertTrue(session.earlierDeepAnalysis.isEmpty)
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let satisfied = await predicate()
        XCTAssertTrue(satisfied)
    }
}

@MainActor
private final class NoDeepRecorder: MobileRecording {
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        onSegment(.init(source: .you, text: "Ship Friday or wait for QA? Speed versus reliability.",
                        isFinal: true, start: 0, end: 3))
    }
    func stop() async throws {}
    func reconfigure() async throws {}
}

/// Answers every evaluation with both a Summary and a Deep recommendation at high confidence.
private actor DeepRecommendingProvider: LLMProvider {
    nonisolated let id = "deep-recommending-test"
    private var systems: [String] = []
    func reviewSystems() -> [String] { systems }
    private func respond(_ request: LLMRequest, to continuation: AsyncThrowingStream<String, Error>.Continuation) {
        if request.purpose == .quickEvaluation {
            continuation.yield("""
            {"action":"publish","context":"Ship Friday or wait","bullets":["Ship Friday or wait for QA."],
            "reviews":[{"mode":"summary","confidence":"high","reason":"New topic"},
            {"mode":"deep","confidence":"high","reason":"Unresolved tradeoff"}]}
            """)
        } else {
            systems.append(request.system)
            continuation.yield("Summary review")
        }
        continuation.finish()
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(request, to: continuation) } }
    }
}
