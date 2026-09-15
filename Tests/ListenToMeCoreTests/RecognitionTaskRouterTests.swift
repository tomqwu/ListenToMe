import XCTest
@testable import ListenToMeCore

/// Issue #108: SFSpeechRecognizer callbacks carry no task identity, so a trailing error from a
/// superseded task tore down the NEW task's state. These tests pin the pure rule that decides which
/// callbacks may act.
final class RecognitionTaskRouterTests: XCTestCase {

    func testCurrentTaskDeliversPartialsAndFinals() {
        var router = RecognitionTaskRouter()
        let token = router.install(for: .you)
        XCTAssertEqual(router.current(for: .you), token)
        XCTAssertEqual(router.action(for: .partial, token: token, source: .you), .deliverPartial)
        XCTAssertEqual(router.action(for: .final, token: token, source: .you), .deliverFinal)
    }

    func testStaleErrorAfterFinalCannotTearDownTheReplacementTask() {
        var router = RecognitionTaskRouter()
        let taskA = router.install(for: .you)
        XCTAssertEqual(router.action(for: .final, token: taskA, source: .you), .deliverFinal)
        XCTAssertTrue(router.mayRestart(token: taskA, for: .you))

        let taskB = router.install(for: .you)
        // The superseded task's trailing cancellation/no-speech error must be ignored entirely.
        XCTAssertEqual(router.action(for: .failure, token: taskA, source: .you), .ignore)
        XCTAssertFalse(router.mayRestart(token: taskA, for: .you))
        XCTAssertEqual(router.current(for: .you), taskB)
        // ...and B is still fully live.
        XCTAssertEqual(router.action(for: .partial, token: taskB, source: .you), .deliverPartial)
    }

    func testLatePartialFromSupersededTaskIsSuppressed() {
        var router = RecognitionTaskRouter()
        let taskA = router.install(for: .others)
        _ = router.action(for: .final, token: taskA, source: .others)
        _ = router.install(for: .others)
        XCTAssertEqual(router.action(for: .partial, token: taskA, source: .others), .ignore)
        XCTAssertEqual(router.action(for: .final, token: taskA, source: .others), .ignore)
    }

    func testCallbacksAfterTheFinalOfTheCurrentTaskAreIgnored() {
        var router = RecognitionTaskRouter()
        let token = router.install(for: .you)
        _ = router.action(for: .final, token: token, source: .you)
        // Restart has not run yet; the same task must not deliver or fail twice.
        XCTAssertEqual(router.action(for: .partial, token: token, source: .you), .ignore)
        XCTAssertEqual(router.action(for: .failure, token: token, source: .you), .ignore)
        XCTAssertTrue(router.mayRestart(token: token, for: .you))
    }

    func testFailureRetiresTheTaskAndBlocksRestart() {
        var router = RecognitionTaskRouter()
        let token = router.install(for: .you)
        XCTAssertEqual(router.action(for: .failure, token: token, source: .you), .reportFailure)
        XCTAssertNil(router.current(for: .you))
        XCTAssertFalse(router.mayRestart(token: token, for: .you))
        XCTAssertEqual(router.action(for: .failure, token: token, source: .you), .ignore)
    }

    func testSourcesAreIndependent() {
        var router = RecognitionTaskRouter()
        let you = router.install(for: .you)
        let others = router.install(for: .others)
        XCTAssertEqual(router.action(for: .failure, token: you, source: .you), .reportFailure)
        XCTAssertEqual(router.action(for: .partial, token: others, source: .others), .deliverPartial)
        XCTAssertEqual(router.action(for: .partial, token: you, source: .others), .ignore)
    }

    func testUnknownSourceIgnoresEverything() {
        var router = RecognitionTaskRouter()
        XCTAssertEqual(router.action(for: .partial, token: UUID(), source: .you), .ignore)
        XCTAssertNil(router.current(for: .you))
        XCTAssertFalse(router.mayRestart(token: UUID(), for: .you))
    }

    func testRetireOnlyAffectsTheMatchingToken() {
        var router = RecognitionTaskRouter()
        let taskA = router.install(for: .you)
        let taskB = router.install(for: .you)
        router.retire(token: taskA, for: .you)
        XCTAssertEqual(router.current(for: .you), taskB)
        router.retire(token: taskB, for: .you)
        XCTAssertNil(router.current(for: .you))
    }

    func testRemoveAllClearsEverySource() {
        var router = RecognitionTaskRouter()
        _ = router.install(for: .you)
        _ = router.install(for: .others)
        router.removeAll()
        XCTAssertNil(router.current(for: .you))
        XCTAssertNil(router.current(for: .others))
    }
}
