import XCTest
@testable import ListenToMeCore

@MainActor
final class FileImportCoordinatorTests: XCTestCase {
    private struct ReadFailure: Error {}

    func testCompletedImportOwnsOneOperationAndThenAllowsAnother() async {
        let coordinator = FileImportCoordinator()
        var transcript: [String] = []
        XCTAssertTrue(coordinator.begin(operation: { transcript.append("First import") }, failed: { _ in XCTFail() }))
        XCTAssertFalse(coordinator.begin(operation: { transcript.append("Duplicate import") }, failed: { _ in XCTFail() }))
        await coordinator.wait()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(transcript, ["First import"])
        XCTAssertTrue(coordinator.begin(operation: { transcript.append("Second import") }, failed: { _ in XCTFail() }))
        await coordinator.wait()
        XCTAssertEqual(transcript, ["First import", "Second import"])
    }

    func testFailureIsReportedAndBusyStateClears() async {
        let coordinator = FileImportCoordinator()
        var errors = 0
        coordinator.begin(operation: { throw ReadFailure() }, failed: { error in
            XCTAssertTrue(error is ReadFailure); errors += 1
        })
        await coordinator.wait()
        XCTAssertEqual(errors, 1)
        XCTAssertFalse(coordinator.isActive)
    }

    func testCancelledImportStaysBusyUntilDrainAndSuppressesLateFailure() async {
        let coordinator = FileImportCoordinator()
        var drain: CheckedContinuation<Void, Never>?
        var errors = 0
        coordinator.begin(operation: {
            await withCheckedContinuation { drain = $0 }
            throw ReadFailure()
        }, failed: { _ in errors += 1 })
        for _ in 0..<200 where drain == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(drain)
        coordinator.cancel()
        XCTAssertTrue(coordinator.isActive, "Cancellation cannot release the transcription slot before drain")
        XCTAssertFalse(coordinator.begin(operation: { XCTFail("Overlapping import") }, failed: { _ in XCTFail() }))
        drain?.resume()
        await coordinator.wait()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(errors, 0)
    }

    func testCancelBeforeExecutionOpensNoMediaOrTranscript() async {
        let coordinator = FileImportCoordinator()
        var opens = 0, transcript: [String] = [], errors = 0
        coordinator.begin(operation: { opens += 1; transcript.append("Unrequested speech") },
                          failed: { _ in errors += 1 })
        coordinator.cancel()
        await coordinator.wait()
        XCTAssertEqual(opens, 0)
        XCTAssertTrue(transcript.isEmpty)
        XCTAssertEqual(errors, 0)
        XCTAssertFalse(coordinator.isActive)
    }
}
