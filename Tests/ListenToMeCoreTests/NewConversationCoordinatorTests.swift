import XCTest
@testable import ListenToMeCore

@MainActor
final class NewConversationCoordinatorTests: XCTestCase {
    func testFinalSpeechIsSavedBeforeNewConversationResets() async {
        let coordinator = NewConversationCoordinator()
        var transcript = "Existing words"
        var saved: String?
        var order: [String] = []
        coordinator.begin(checkpoint: { order.append("checkpoint") }, stop: {
            order.append("drain"); transcript += " and final words"
        }, persist: {
            order.append("save"); saved = transcript; return true
        }, resolveUnsaved: { XCTFail("Successful history save needs no prompt"); return false }, reset: { persisted in
            XCTAssertTrue(persisted); order.append("reset"); transcript = ""
        })
        XCTAssertTrue(coordinator.isBusy, "A second New is blocked before its task starts")
        await coordinator.wait()
        XCTAssertEqual(order, ["checkpoint", "drain", "save", "reset"])
        XCTAssertEqual(saved, "Existing words and final words")
        XCTAssertEqual(transcript, "")
        XCTAssertFalse(coordinator.isBusy)
    }

    func testCancelledOrFailedSaveAsKeepsTheConversation() async {
        let coordinator = NewConversationCoordinator()
        var title = "Keep this conversation", decisions = 0
        coordinator.begin(checkpoint: {}, stop: {}, persist: { false }, resolveUnsaved: {
            decisions += 1; return false
        }, reset: { _ in title = "New conversation" })
        await coordinator.wait()
        XCTAssertEqual(title, "Keep this conversation")
        XCTAssertEqual(decisions, 1)
        XCTAssertFalse(coordinator.isBusy)
    }

    func testAcceptedSaveAsOrExplicitDiscardResetsOnlyAfterDecision() async {
        let coordinator = NewConversationCoordinator()
        var order: [String] = []
        coordinator.begin(checkpoint: {}, stop: {}, persist: { false }, resolveUnsaved: {
            order.append("explicit decision"); return true
        }, reset: { persisted in
            XCTAssertFalse(persisted, "An export or discard does not claim a durable history save")
            order.append("reset")
        })
        await coordinator.wait()
        XCTAssertEqual(order, ["explicit decision", "reset"])
    }

    func testRepeatedNewWhileDrainingCannotPromptOrResetTwice() async {
        let coordinator = NewConversationCoordinator()
        var reply: CheckedContinuation<Void, Never>?
        var prompts = 0, resets = 0
        XCTAssertTrue(coordinator.begin(checkpoint: {}, stop: {
            await withCheckedContinuation { reply = $0 }
        }, persist: { false }, resolveUnsaved: { prompts += 1; return true }, reset: { _ in resets += 1 }))
        for _ in 0..<200 where reply == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(reply)
        XCTAssertFalse(coordinator.begin(checkpoint: { XCTFail("Duplicate New") }, stop: {}, persist: { false },
                                         resolveUnsaved: { prompts += 1; return true }, reset: { _ in resets += 1 }))
        XCTAssertEqual(prompts, 0)
        reply?.resume()
        await coordinator.wait()
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(resets, 1)
    }
}
