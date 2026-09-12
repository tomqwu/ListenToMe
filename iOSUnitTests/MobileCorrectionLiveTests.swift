import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileCorrectionLiveTests: XCTestCase {
    /// Explicit local credential staging only. Exercises the actual Cloud client and session flow, with synthetic speech.
    func testLiveFlashCorrectionThroughRecordingSaveAndRestore() async throws {
        let keyFile = URL.applicationSupportDirectory.appendingPathComponent("OllamaCorrectionTestKey")
        guard FileManager.default.fileExists(atPath: keyFile.path) else { throw XCTSkip("Requires a locally staged test credential.") }
        let key = try String(contentsOf: keyFile, encoding: .utf8)
        try FileManager.default.removeItem(at: keyFile)
        let originalKey = try MobileKeychain.read()
        let keys = ["mobileCorrectTranscript", "mobileCorrectionModel", "mobileOllamaCatalog",
                    "mobileOllamaModel", "mobileOllamaQuickModel", "mobileOllamaDeepModel", "autoQuickSummary"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recorder = CorrectionTestRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        defer {
            session.state = .idle; session.ai.correctTranscript = false; session.autoQuick = false
            try? MobileKeychain.save(originalKey)
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        session.autoQuick = false; session.ai.correctTranscript = false
        XCTAssertTrue(session.ai.saveKey(key))
        session.ai.correctionModel = ""
        await session.ai.refresh()
        XCTAssertNil(session.ai.correctionAvailability)
        session.start()
        for _ in 0..<100 where session.state != .recording { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(session.state, .recording)
        recorder.send("We are discussing meeting notes and action items.")
        session.ai.correctTranscript = true
        let started = ContinuousClock.now
        recorder.send("Please send the meeting goats to Alex.")
        for _ in 0..<700 where session.speechCorrection.working { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(session.speechCorrection.working)
        let corrected = try XCTUnwrap(session.segments.last)
        XCTAssertEqual(corrected.text, "Please send the meeting notes to Alex.", session.speechCorrectionStatus)
        XCTAssertEqual(corrected.originalText, "Please send the meeting goats to Alex.")
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(13))
        await session.stop()
        XCTAssertEqual(MobileSession(storageDirectory: root).segments.last, corrected)
        session.restoreSpeech(corrected.id)
        XCTAssertEqual(session.segments.last?.text, corrected.originalText)
        XCTAssertNil(session.segments.last?.originalText)
        // Repeated live calls caught an intermittent Cloud preamble without a closing think tag.
        // Keep this a local, credential-gated contract check rather than relying on one lucky response.
        for _ in 0..<5 {
            let text = try await MobileTranscriptCorrector.correct("Please send the meeting goats to Alex.",
                context: "We are discussing meeting notes and action items.", provider: session.ai.correctionClient())
            XCTAssertEqual(text, "Please send the meeting notes to Alex.")
        }
    }
}
