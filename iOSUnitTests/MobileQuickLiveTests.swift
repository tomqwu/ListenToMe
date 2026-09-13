import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileQuickLiveTests: XCTestCase {
    /// Actual Cloud transport + recording event loop. Synthetic speech only; no physical microphone claim.
    func testLiveFlashEvaluatesKeepsRevisesAndSuggestsReview() async throws {
        let keyFile = URL.applicationSupportDirectory.appendingPathComponent("OllamaQuickTestKey")
        guard FileManager.default.fileExists(atPath: keyFile.path) else { throw XCTSkip("Requires a locally staged test credential.") }
        let key = try String(contentsOf: keyFile, encoding: .utf8)
        try FileManager.default.removeItem(at: keyFile)
        let originalKey = try MobileKeychain.read()
        let keys = ["mobileAIProvider", "mobileCorrectTranscript", "mobileOllamaCatalog", "mobileCorrectionModel",
                    "mobileOllamaModel", "mobileOllamaQuickModel", "mobileOllamaDeepModel", "autoQuickSummary"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recorder = QuickTestRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        defer {
            session.autoQuick = false; session.state = .idle
            try? MobileKeychain.save(originalKey)
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        session.autoQuick = false; session.ai.correctTranscript = false
        XCTAssertTrue(session.ai.saveKey(key))
        session.ai.provider = .ollama
        session.ai.quickModel = ""
        await session.ai.refresh()
        session.ai.quickModel = "glm-5.3-flash"
        session.ai.model = "glm-5.3"; session.ai.deepModel = "glm-5.3"
        XCTAssertNil(session.ai.availability(for: .quick))
        XCTAssertTrue(MobileAISettings.isFlash(session.ai.quickModel))
        session.autoQuick = true
        session.start()
        try await wait { session.state == .recording }
        print("Live evaluator completed reads: \(session.quickReader.completedReads); error: \(session.quickReader.error ?? "none")")
        recorder.send("Hello everyone. Good morning.")
        try await waitForRead(1, session: session)
        XCTAssertEqual(session.quickSummary, "")
        print("Live evaluator completed reads: \(session.quickReader.completedReads); error: \(session.quickReader.error ?? "none")")
        recorder.send("Uh, this is a test for Azure Cloud.")
        try await waitForRead(2, session: session)
        XCTAssertTrue(session.quickSummary.contains("Azure"), "A named topic should produce the first recap")
        recorder.send("Help me understand the APM management.")
        try await waitForRead(3, session: session)
        XCTAssertTrue(session.quickSummary.contains("APM"), "A question is useful summary material without a decision")
        XCTAssertFalse(session.quickSummary.lowercased().contains("application performance"), "Do not expand an ambiguous acronym")
        try await wait { (session.automaticReviews.completedCounts[.summary] ?? 0) > 0 }
        try await wait { (session.automaticReviews.completedCounts[.deep] ?? 0) > 0 }
        XCTAssertFalse(session.summary.isEmpty)
        XCTAssertFalse(session.deepThought.isEmpty)
        XCTAssertTrue(session.deepThought.localizedCaseInsensitiveContains("APM"))
        recorder.send("We agree delivery on Monday. Sarah will confirm. The budget is 150 dollars.", final: false)
        try await waitForRead(4, session: session)
        XCTAssertTrue(session.quickSummary.contains("Monday"))
        XCTAssertTrue(session.quickSummary.contains("Sarah"))
        XCTAssertTrue(session.quickSummary.contains("150"))
        XCTAssertEqual(session.finalizedSpeechEventCount, 3, "Decision must publish before recognition finalizes")
        recorder.send("We agree delivery on Monday. Sarah will confirm. The budget is 150 dollars.")
        try await waitForRead(5, session: session)
        let decision = session.quickSummary
        print("Live evaluator completed reads: \(session.quickReader.completedReads); error: \(session.quickReader.error ?? "none")")
        recorder.send("Yes, understood. That is what we agreed.")
        try await waitForRead(6, session: session)
        XCTAssertEqual(session.quickSummary, decision, "Repetition should be read without rewriting the bullets")
        print("Live evaluator completed reads: \(session.quickReader.completedReads); error: \(session.quickReader.error ?? "none")")
        recorder.send("改到周二交付，Peter负责确认。预算仍然是150美元。")
        try await waitForRead(7, session: session)
        XCTAssertTrue(session.quickSummary.contains("Peter"))
        XCTAssertFalse(session.quickSummary.contains("Sarah"), "Corrected recap: \(session.quickSummary)")
        XCTAssertTrue(session.quickSummary.contains("150"))
        print("Live evaluator completed reads: \(session.quickReader.completedReads); error: \(session.quickReader.error ?? "none")")
        recorder.send("Shipping sooner risks data loss; delaying could lose a customer. This tradeoff remains unresolved.")
        try await waitForRead(8, session: session)
        XCTAssertFalse(session.deepThought.isEmpty, "The earlier APM question should have triggered Deep automatically")
        XCTAssertFalse(session.quickSummary.contains("\"action\""))
        await session.stop()
        await session.summarize(mode: .quick)
        XCTAssertNil(session.quickSummaryError)
        XCTAssertTrue(session.quickSummary.contains("Peter"))
        XCTAssertFalse(session.quickSummary.contains("\"action\""))
        XCTAssertLessThanOrEqual(session.quickSummary.count, 490)
        XCTAssertLessThanOrEqual(session.quickSummary.split(separator: "\n").count, 3)
        XCTAssertEqual(MobileSession(storageDirectory: root).quickSummary, session.quickSummary)
        XCTAssertTrue(session.markdown.contains("Peter"))
    }

    private func waitForRead(_ count: Int, session: MobileSession) async throws {
        let deadline = ContinuousClock.now + .seconds(90)
        var last = ""
        while session.quickReader.completedReads < count, ContinuousClock.now < deadline {
            let status = "reads=\(session.quickReader.completedReads), failures=\(session.quickReader.failures)"
                + ", error=\(session.quickReader.error ?? "none")"
                + ", full=\(session.automaticReviews.activeMode?.rawValue ?? "idle")"
            if status != last { print("Live diagnostics: " + status); last = status }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(session.quickReader.completedReads, count, last)
        print("Live recap: " + session.quickSummary)
        if session.quickReader.completedReads != count { throw URLError(.timedOut) }
    }

    private func wait(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(90)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), "Live evaluator did not reach expected state", file: file, line: line)
        if !condition() { throw URLError(.timedOut) }
    }
}
