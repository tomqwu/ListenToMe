import XCTest
@testable import ListenToMeCore

@MainActor
final class ConversationCloseCoordinatorTests: XCTestCase {
    func testCancelledCloseKeepsPendingCalendarAndReferenceContext() async {
        await checkPendingContext(canBegin: true, userAccepts: false, expectedPublications: 2)
    }

    func testBusyRefusalDoesNotCancelPendingContextOrAskToSave() async {
        await checkPendingContext(canBegin: false, userAccepts: true, expectedPublications: 2)
    }

    func testAcceptedCloseInvalidatesBothPendingContextSources() async {
        await checkPendingContext(canBegin: true, userAccepts: true, expectedPublications: 0)
    }

    private func checkPendingContext(canBegin: Bool, userAccepts: Bool, expectedPublications: Int) async {
        let calendar = CalendarContextCoordinator()
        let reference = ReferenceContextCoordinator()
        let closer = ConversationCloseCoordinator()
        let reader = CloseHeldReference()
        var calendarReply: CheckedContinuation<CalendarLookup, Never>?
        var publications = 0, decisions = 0
        let calendarWork = calendar.load(snapshot: {
            .init(conversationID: "current", notes: "", title: "New conversation", titleState: .placeholder)
        }, lookup: { await withCheckedContinuation { calendarReply = $0 } },
        timeFormat: { _ in "unused" }, apply: { _ in publications += 1 })
        let referenceWork = reference.load([], maxChars: 500, read: { _ in await reader.read() },
                                           apply: { _ in publications += 1 })
        for _ in 0..<200 {
            if calendarReply != nil, await reader.waiting { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(calendarReply)
        let reading = await reader.waiting
        XCTAssertTrue(reading)
        let closed = await closer.request(canBegin: canBegin, prepare: {
            decisions += 1; return userAccepts
        }, accepted: { calendar.cancel(); reference.cancel() })
        XCTAssertEqual(closed, canBegin && userAccepts)
        XCTAssertEqual(decisions, canBegin ? 1 : 0)
        calendarReply?.resume(returning: .meeting(MeetingInfo(title: "Selected event")))
        await reader.finish()
        await calendarWork.value
        await referenceWork.value
        XCTAssertEqual(publications, expectedPublications,
                       "A rejected close keeps pending context usable; an accepted close discards it")
    }

    func testOverlappingCloseCannotPromptOrInvalidateTwice() async {
        let closer = ConversationCloseCoordinator()
        var reply: CheckedContinuation<Bool, Never>?
        var decisions = 0, invalidations = 0
        let first = Task {
            await closer.request(canBegin: true, prepare: {
                decisions += 1
                return await withCheckedContinuation { reply = $0 }
            }, accepted: { invalidations += 1 })
        }
        for _ in 0..<200 where reply == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(reply)
        let second = await closer.request(canBegin: true, prepare: { decisions += 1; return true },
                                          accepted: { invalidations += 1 })
        XCTAssertFalse(second)
        reply?.resume(returning: true)
        let firstAccepted = await first.value
        XCTAssertTrue(firstAccepted)
        XCTAssertEqual(decisions, 1)
        XCTAssertEqual(invalidations, 1)
    }
}

private actor CloseHeldReference {
    private var reply: CheckedContinuation<FileContextLoader.Result, Never>?
    var waiting: Bool { reply != nil }
    func read() async -> FileContextLoader.Result { await withCheckedContinuation { reply = $0 } }
    func finish() {
        reply?.resume(returning: .init(documents: [.init(name: "selected.txt", content: "Selected local content")]))
        reply = nil
    }
}
