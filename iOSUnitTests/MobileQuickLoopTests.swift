import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileQuickLoopTests: XCTestCase {
    private var root: URL!
    private var session: MobileSession!
    private var recorder: QuickTestRecorder!
    private var provider: QuickTestProvider!
    private var savedAuto = false

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        recorder = QuickTestRecorder()
        provider = QuickTestProvider()
        let recorder = recorder!
        session = MobileSession(storageDirectory: root, summaryProvider: provider, autoInterval: .milliseconds(80),
                                makeRecorder: { recorder })
        savedAuto = session.autoQuick
        session.autoQuick = true
    }

    override func tearDown() async throws {
        session.autoQuick = false
        session.cancelSummary()
        await session.stop()
        await provider.finishAll()
        UserDefaults.standard.set(savedAuto, forKey: "autoQuickSummary")
        try? FileManager.default.removeItem(at: root)
        session = nil; provider = nil; recorder = nil
    }

    func testRecordingChecksGreetingPublishesDecisionAndPreservesOutputOnRepetition() async throws {
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Hello everyone.")
        try await wait { self.session.quickReader.completedReads == 1 }
        XCTAssertEqual(session.quickSummary, "")
        XCTAssertTrue(session.autoQuickStatus.contains("Speech checked · No takeaway yet"))
        await session.stop()
        XCTAssertTrue(session.autoQuickStatus.contains("Speech checked · No takeaway yet"))
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday is agreed. Sarah confirms.")
        try await wait { self.session.quickReader.completedReads == 2 }
        let decision = session.quickSummary
        XCTAssertEqual(decision, "- Monday is agreed. Sarah confirms.")
        recorder.send("Yes, understood.")
        try await wait { self.session.quickReader.completedReads == 3 }
        XCTAssertEqual(session.quickSummary, decision)
        XCTAssertTrue(session.autoQuickStatus.contains("Summary unchanged"))
        let inputs = await provider.inputs()
        XCTAssertEqual(inputs[1].runningContext, "Hello everyone.")
        XCTAssertEqual(inputs[1].changes.map(\.text), ["Microphone: Monday is agreed. Sarah confirms."],
                       "Automatic evaluation must see who said it")
        try await Task.sleep(for: .milliseconds(250))
        let count = await provider.count()
        XCTAssertEqual(count, 3, "Silence must not call the model")
        await session.stop()
        XCTAssertEqual(MobileSession(storageDirectory: root).quickSummary, decision)
    }

    func testRemovingAllSourceClearsQuickWithoutAnotherModelCall() async throws {
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday is agreed. Sarah confirms.")
        try await wait { self.session.quickReader.completedReads == 1 }
        XCTAssertFalse(session.quickSummary.isEmpty)
        session.segments = []
        try await wait { self.session.quickSummary.isEmpty }
        let count = await provider.count()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(session.quickReader.recommendations.isEmpty)
    }

    func testRepeatedManualReviewDuringReadCannotResurrectSuggestion() async throws {
        await provider.suggestSummary()
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday is agreed.")
        try await wait { self.session.quickReader.completedReads == 1 }
        XCTAssertEqual(session.quickReader.recommendations.count, 1)
        session.quickReader.markReviewed(.summary)
        await provider.holdNextQuick()
        recorder.send("Tuesday is now agreed.")
        try await wait { await self.provider.hasHeldQuick() }
        session.quickReader.markReviewed(.summary)
        await provider.finishHeldQuick()
        try await wait { self.session.quickReader.completedReads == 2 }
        XCTAssertTrue(session.quickReader.recommendations.isEmpty)
        XCTAssertEqual(session.quickReader.reviewsCompleted, ["summary"])
    }

    func testSubstantialLiveSpeechTriggersQuickBeforeRecognizerFinalizes() async throws {
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Peter will deliver the prototype on Wednesday.", final: false)
        try await wait { self.session.quickReader.completedReads == 1 }
        XCTAssertTrue(session.segments.isEmpty, "The recognizer has not finalized any speech")
        XCTAssertEqual(session.quickSummary, "- Peter will deliver the prototype on Wednesday.")
        let count = await provider.count()
        try await Task.sleep(for: .milliseconds(250))
        let unchangedCount = await provider.count()
        XCTAssertEqual(unchangedCount, count, "Idle time alone must not poll the model")
        recorder.send("Correction: Peter will deliver on Thursday.")
        try await wait { self.session.quickReader.completedReads == 2 }
        XCTAssertTrue(session.quickSummary.contains("Thursday"))
        XCTAssertFalse(session.quickSummary.contains("Wednesday"))
    }

    func testShortSpeechFragmentsWaitAndFinalBurstCoalesces() async throws {
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday", final: false)
        recorder.send("Monday is", final: false)
        try await Task.sleep(for: .milliseconds(200))
        let partialCount = await provider.count()
        XCTAssertEqual(partialCount, 0)
        recorder.send("Monday is agreed.")
        recorder.send("Sarah confirms.")
        recorder.send("The team agrees.")
        try await wait { self.session.quickReader.completedReads == 1 }
        let inputs = await provider.inputs()
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].changes.count, 3)
        XCTAssertNil(session.partial)
    }

    func testSlowReadCoalescesQueuedSpeechAndDeepDoesNotBlockQuick() async throws {
        await provider.holdNextQuick()
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday is agreed.")
        try await wait { await self.provider.hasHeldQuick() }
        recorder.send("Sarah confirms.")
        recorder.send("Peter helps.")
        try await Task.sleep(for: .milliseconds(150))
        let duringSlow = await provider.count()
        XCTAssertEqual(duringSlow, 1)
        await provider.finishHeldQuick()
        try await wait { self.session.quickReader.completedReads == 2 }
        let inputs = await provider.inputs()
        XCTAssertEqual(inputs[1].changes.map(\.text), ["Microphone: Sarah confirms.", "Microphone: Peter helps."])
        session.requestSummary(for: .deep)
        try await wait { self.session.generatingMode == .deep }
        recorder.send("Monday remains agreed.")
        try await wait { self.session.quickReader.completedReads == 3 }
        XCTAssertEqual(session.generatingMode, .deep, "Quick completes while Deep is still in flight")
        let maxQuick = await provider.maxQuick()
        XCTAssertEqual(maxQuick, 1)
    }

    func testOffAndStopCancelInFlightWithoutOverwritingSavedSummaryOrNewConversation() async throws {
        session.quickSummary = "Previous summary"
        await provider.holdNextQuick()
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday is agreed.")
        try await wait { await self.provider.hasHeldQuick() }
        session.autoQuick = false
        await provider.finishHeldQuick()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(session.quickSummary, "Previous summary")
        XCTAssertEqual(session.quickReader.completedReads, 0)
        session.autoQuick = true
        try await wait { self.session.quickReader.completedReads == 1 }
        await provider.holdNextQuick()
        recorder.send("A late decision.")
        try await wait { await self.provider.hasHeldQuick() }
        await session.stop()
        session.newConversation()
        await provider.finishHeldQuick()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(session.quickSummary, "")
        XCTAssertEqual(session.quickReader.completedReads, 0)
        XCTAssertTrue(session.segments.isEmpty)
    }

    func testMalformedResponseRetriesSameUnreadTextAndKeepsPreviousSummary() async throws {
        session.quickSummary = "Previous summary"
        await provider.failNextQuick()
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Monday is agreed.")
        try await wait { self.session.quickSummaryError != nil }
        XCTAssertEqual(session.quickSummary, "Previous summary")
        XCTAssertEqual(session.quickReader.completedReads, 0)
        try await wait { self.session.quickReader.completedReads == 1 }
        XCTAssertNil(session.quickSummaryError)
        let inputs = await provider.inputs()
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs[0].changes.map(\.text), inputs[1].changes.map(\.text))
    }

    func testCorrectionDuringRequestRejectsOldSnapshotAndResendsRevisedText() async throws {
        await provider.holdNextQuick()
        session.start()
        try await wait { self.session.state == .recording }
        recorder.send("Sarah confirms.")
        try await wait { await self.provider.hasHeldQuick() }
        session.segments[0] = session.segments[0].withCorrection("Peter confirms.", model: "test")
        await provider.finishHeldQuick()
        try await wait { self.session.quickReader.completedReads == 1 }
        XCTAssertEqual(session.quickSummary, "- Peter confirms.")
        XCTAssertFalse(session.quickSummary.contains("Sarah"))
        session.restoreSpeech(session.segments[0].id)
        try await wait { self.session.quickReader.completedReads == 2 }
        let inputs = await provider.inputs()
        XCTAssertEqual(inputs.last?.changes[0].previousText, "Microphone: Peter confirms.")
        XCTAssertEqual(inputs.last?.changes[0].text, "Microphone: Sarah confirms.")
    }

    func testAppleAutomaticEvaluationPausesWithoutEnablingCloud() {
        let local = MobileSession(storageDirectory: root.appendingPathComponent("local"))
        let original = local.ai.provider
        defer { local.state = .idle; local.ai.provider = original }
        local.ai.provider = .apple
        local.notes = "A meeting decision"
        local.autoQuick = true
        local.state = .recording
        XCTAssertEqual(local.automaticQuickAvailability, AppleIntelligenceProvider.automaticQuickUnavailableReason)
        XCTAssertEqual(local.ai.provider, .apple)
        XCTAssertFalse(local.quickReader.isReading)
        XCTAssertEqual(local.quickReader.completedReads, 0)
    }

    func testDeadlineCancelsAnUnresponsiveStream() async throws {
        let provider = QuickTestProvider()
        await provider.holdNextQuick()
        let request = LLMRequest(system: MobileQuickContext.instructions, messages: [])
        let start = ContinuousClock.now
        do {
            _ = try await MobileQuickReader.evaluate(request, provider: provider, timeout: .milliseconds(80))
            XCTFail("A stream without a response must time out")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
        await provider.finishAll()
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let satisfied = await predicate()
        XCTAssertTrue(satisfied)
    }
}

@MainActor
final class QuickTestRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    private var index = 0
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { receive = onSegment }
    func send(_ text: String, final: Bool = true) {
        receive?(.init(source: .you, text: text, isFinal: final, start: Double(index), end: Double(index + 1)))
        if final { index += 1 }
    }
    func stop() async throws { receive = nil }
}

private actor QuickTestProvider: LLMProvider {
    nonisolated let id = "quick-loop-test"
    private var captured: [MobileQuickContext.Input] = []
    private var held: AsyncThrowingStream<String, Error>.Continuation?
    private var heldText = ""
    private var deep: AsyncThrowingStream<String, Error>.Continuation?
    private var hold = false
    private var fail = false
    private var active = 0
    private var maximum = 0
    private var reviews: [[String: String]] = []
    func suggestSummary() { reviews = [["mode": "summary", "confidence": "high", "reason": "Decision changed"]] }
    func inputs() -> [MobileQuickContext.Input] { captured }
    func count() -> Int { captured.count }
    func maxQuick() -> Int { maximum }
    func holdNextQuick() { hold = true }
    func hasHeldQuick() -> Bool { held != nil }
    func failNextQuick() { fail = true }
    func finishHeldQuick() { held?.yield(heldText); held?.finish(); held = nil }
    func finishAll() { finishHeldQuick(); deep?.finish(); deep = nil }
    private func ended() { active -= 1 }
    /// Pieces now arrive attributed ("Microphone: …", "Notes: …"); a real model answers with the
    /// content, so the stub drops the leading label before echoing it back as a recap.
    private func spoken(_ text: String) -> String {
        guard let separator = text.range(of: ": ") else { return text }
        return String(text[separator.upperBound...])
    }

    private func respond(_ request: LLMRequest, _ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        guard request.system == MobileQuickContext.instructions else { deep = continuation; return }
        active += 1; maximum = max(maximum, active)
        continuation.onTermination = { _ in Task { await self.ended() } }
        let input = try? JSONDecoder().decode(MobileQuickContext.Input.self, from: Data((request.messages.first?.content ?? "").utf8))
        if let input { captured.append(input) }
        let text = input?.changes.map(\.text).filter { !$0.isEmpty }.map(spoken).joined(separator: " ") ?? ""
        let keep = text == "Hello everyone." || text == "Yes, understood."
        let data = try? JSONSerialization.data(withJSONObject: ["reviews": reviews, "action": keep ? "keep" : "publish",
            "context": text, "bullets": keep ? [] : [text]])
        let response = String(decoding: data ?? Data(), as: UTF8.self)
        if hold { hold = false; held = continuation; heldText = response; return }
        if fail { fail = false; continuation.yield("{broken"); continuation.finish(); return }
        continuation.yield(response); continuation.finish()
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(request, continuation) } }
    }
}
