import XCTest
@testable import ListenToMeCore

@MainActor
final class TranslationRecoveryTests: XCTestCase {
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testStalledReadinessAndInferenceReachTimeoutWithoutMultiplyingWorkAndRetryAfterDrain() async {
        for phase in [HeldTranslation.Phase.readiness, .inference] {
            let service = HeldTranslation(phase: phase)
            let translation = SummaryTranslationCoordinator(translator: service, requestTimeout: .milliseconds(40))
            let original = "The meeting starts tomorrow.\nPlease review the agenda."
            translation.update(source: original, conversationID: "a", target: "zh-Hans")
            translation.request()
            await settle { service.isHeld }
            XCTAssertTrue(service.isHeld)
            XCTAssertFalse(translation.canRequest, "An active request cannot be submitted twice")
            await settle { !translation.worker.isTranslating }
            XCTAssertFalse(translation.worker.isTranslating, "A held native call must not promise progress forever")
            XCTAssertTrue(translation.worker.isDraining)
            XCTAssertTrue(translation.worker.availability.reason?.contains("stopped responding") == true)
            XCTAssertEqual(translation.source, original)
            XCTAssertNil(translation.translatedText)
            let failures = translation.worker.problems
            for _ in 0..<8 { translation.request(); translation.worker.retry() }
            XCTAssertEqual(translation.worker.problems, failures, "Retry must not erase recovery guidance while stopping")
            XCTAssertLessThanOrEqual(service.maximumActive, 1)
            service.release()
            await settle { !translation.worker.isDraining }
            XCTAssertNil(translation.translatedText, "Late output after timeout is never published")
            XCTAssertTrue(translation.canRequest)
            translation.request()
            await settle { translation.translatedText != nil }
            XCTAssertEqual(translation.translatedText, "会议明天开始。\n请查看议程。")
            XCTAssertEqual(translation.source, original)
            XCTAssertEqual(service.maximumActive, 1)
        }
    }

    func testCancelTargetAndConversationChangesEndProgressAndFenceLateResults() async {
        for change in ["cancel", "target", "conversation"] {
            let service = HeldTranslation(phase: .inference)
            let translation = SummaryTranslationCoordinator(translator: service)
            let original = "The meeting starts tomorrow."
            translation.update(source: original, conversationID: "a", target: "zh-Hans")
            translation.request(); await settle { service.isHeld }
            switch change {
            case "cancel": translation.cancel()
            case "target": translation.update(source: original, conversationID: "a", target: "fr")
            default: translation.update(source: "A different summary.", conversationID: "b", target: "zh-Hans")
            }
            XCTAssertFalse(translation.worker.isTranslating, change)
            XCTAssertTrue(translation.worker.isDraining, change)
            XCTAssertFalse(translation.canRequest)
            XCTAssertNil(translation.translatedText)
            XCTAssertGreaterThan(service.cancellations, 0)
            service.release(); await settle { !translation.worker.isDraining && !translation.worker.isTranslating }
            if change == "target" {
                XCTAssertEqual(translation.translatedText, "La réunion commence demain.")
            } else {
                XCTAssertNil(translation.translatedText)
            }
            XCTAssertEqual(service.maximumActive, 1)
        }
    }

    func testSuccessfulCompletionCancelsDeadlineAndRetainsTranslation() async {
        let service = HeldTranslation(phase: nil)
        let translation = SummaryTranslationCoordinator(translator: service, requestTimeout: .milliseconds(40))
        translation.update(source: "The meeting starts tomorrow.", conversationID: "a", target: "zh-Hans")
        translation.request(); await settle { translation.translatedText != nil }
        let calls = service.calls
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(translation.translatedText, "会议明天开始。")
        XCTAssertEqual(service.calls, calls)
        XCTAssertTrue(translation.worker.problems.isEmpty)
        XCTAssertFalse(translation.worker.isTranslating)
        XCTAssertFalse(translation.worker.isDraining)
        XCTAssertTrue(translation.canRequest)
    }

    func testCompletedParagraphDeadlineCannotCancelTheNextParagraph() async {
        let service = HeldTranslation(phase: .inference)
        service.holdInferenceOnCall = 2
        let translation = SummaryTranslationCoordinator(translator: service)
        var deadlines: [CheckedContinuation<Void, Never>] = []
        // Models a timer already ready to resume when its owner cancels it.
        translation.worker.deadlineWait = { _ in
            await withCheckedContinuation { deadlines.append($0) }
        }
        translation.update(source: "The meeting starts tomorrow.\nPlease review the agenda.",
                           conversationID: "a", target: "zh-Hans")
        translation.request()
        await settle { service.isHeld && deadlines.count == 2 }
        XCTAssertEqual(deadlines.count, 2)
        guard deadlines.count == 2 else { service.release(); deadlines.forEach { $0.resume() }; return }
        deadlines.removeFirst().resume()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(translation.worker.isTranslating, "An obsolete timer must not stop the next paragraph")
        XCTAssertTrue(translation.worker.problems.isEmpty)
        XCTAssertFalse(translation.worker.isDraining)
        service.release()
        await settle { translation.translatedText != nil }
        deadlines.forEach { $0.resume() }
        XCTAssertEqual(translation.translatedText, "会议明天开始。\n请查看议程。")
    }
}

@MainActor private final class HeldTranslation: TranscriptTranslating {
    enum Phase { case readiness, inference }
    private var phase: Phase?
    private var held: CheckedContinuation<Void, Never>?
    private var active = 0
    var maximumActive = 0
    var calls = 0
    var holdInferenceOnCall = 1
    var cancellations = 0
    var isHeld: Bool { held != nil }
    init(phase: Phase?) { self.phase = phase }
    func release() { held?.resume(); held = nil }
    private func wait(_ phase: Phase) async {
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if self.phase == phase && (phase == .readiness || calls == holdInferenceOnCall) {
            self.phase = nil
            await withCheckedContinuation { held = $0 }
        }
    }
    func sourceLanguage(for text: String, hint: String?) -> String? { "en" }
    func availability(source: String, target: String) async -> FeatureAvailability {
        await wait(.readiness); return .ready
    }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        calls += 1; await wait(.inference)
        if target == "fr" { return "La réunion commence demain." }
        return text.contains("review") ? "请查看议程。" : "会议明天开始。"
    }
    // Deliberately uncooperative: proves the coordinator's bounded state, not native model accuracy.
    func cancel() { cancellations += 1 }
}
