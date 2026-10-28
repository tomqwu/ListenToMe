import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileLanguageUndoContinuityTests: MobileLanguageTestCase {
    func testHeldUndoContextCannotSwitchInactiveAndForegroundCanRetry() async throws {
        let session = try await switchToMandarinAtOneMinute()
        var active = true
        session.applicationIsActive = { active }
        recorder.holdContext = true
        session.undoLanguageSwitch()
        for _ in 0..<400 where !recorder.isHoldingContext { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingContext)
        active = false
        await session.handleScenePhase(.inactive)
        recorder.holdContext = false
        recorder.releaseContext()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(recorder.switches.count, 1, "Inactive Undo must not start native replacement after context returns")
        XCTAssertTrue(session.languageDetection.automatic)
        XCTAssertEqual(session.languageDetection.notice?.to, "zh-CN")
        active = true
        await session.handleScenePhase(.active)
        session.undoLanguageSwitch()
        for _ in 0..<400 where recorder.switches.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(recorder.switches.count, 2)
        XCTAssertFalse(session.languageDetection.automatic)
        await session.stop()
    }

    func testHeldUndoNativePreparationCannotCommitAfterInactive() async throws {
        let session = try await switchToMandarinAtOneMinute()
        var active = true
        session.applicationIsActive = { active }
        recorder.holdSwitch = true
        session.undoLanguageSwitch()
        for _ in 0..<400 where !recorder.isHoldingSwitch { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingSwitch)
        active = false
        await session.handleScenePhase(.inactive)
        recorder.releaseSwitch()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(recorder.switches.count, 1)
        XCTAssertTrue(session.languageDetection.automatic)
        XCTAssertFalse(session.languageDetection.undoing)
        XCTAssertEqual(session.state, .recording)
        await session.stop()
    }

    func testStoppedUndoFailureCannotPinOrMutateANewConversation() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        recorder.holdSwitch = true
        session.undoLanguageSwitch()
        for _ in 0..<400 where !recorder.isHoldingSwitch { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingSwitch)
        await session.stop()
        session.newConversation()
        session.languageChoice = "es-ES"
        let conversation = session.id
        recorder.releaseSwitch(failing: CancellationError())
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(session.id, conversation)
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertEqual(session.languageChoice, "es-ES", "A stale Undo error cannot change the next conversation's language")
        XCTAssertNil(session.message)
    }

    func testUndoPinsAtNativeCommitAndHasNoLateEffectAfterStopAndNew() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        let previous = try XCTUnwrap(session.languageDetection.notice?.from)
        recorder.holdPostCommit = true
        session.undoLanguageSwitch()
        for _ in 0..<400 where !recorder.isHoldingPostCommit { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingPostCommit)
        XCTAssertEqual(session.recordingLanguage, previous, "Metadata must match the already committed native locale")
        XCTAssertFalse(session.languageDetection.automatic)
        XCTAssertNil(session.languageDetection.notice)
        await session.stop()
        session.newConversation()
        session.languageChoice = "es-ES"
        let conversation = session.id
        recorder.releasePostCommit()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(session.id, conversation)
        XCTAssertEqual(session.languageChoice, "es-ES", "An old post-commit await must not pin a new conversation")
        XCTAssertTrue(session.segments.isEmpty)
    }

    func testStopCancelsHeldUndoBeforeDrainSoExplicitUndoCanQueue() async throws {
        let session = try await switchToMandarinAtOneMinute()
        session.applicationIsActive = { true }
        let previous = try XCTUnwrap(session.languageDetection.notice?.from)
        recorder.holdContext = true
        recorder.holdStop = true
        session.undoLanguageSwitch()
        for _ in 0..<400 where !recorder.isHoldingContext { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(recorder.isHoldingContext)
        let stopping = Task { await session.stop() }
        for _ in 0..<400 where !recorder.isHoldingStop { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .stopping)
        XCTAssertTrue(session.canUndoLanguageSwitch, "After Stop cancels preparation, explicit Undo remains queueable during drain")
        session.undoLanguageSwitch()
        recorder.holdContext = false
        recorder.releaseContext()
        recorder.releaseStop()
        await stopping.value
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.languageChoice, previous, "The explicit stopping-time Undo applies after final words drain")
        XCTAssertEqual(recorder.switches.count, 1, "Cancelled native preparation must not replace a stopping recorder")
    }

}
