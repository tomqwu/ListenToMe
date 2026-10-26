import XCTest
@testable import ListenToMeCore

@MainActor
final class CalendarContextCoordinatorTests: XCTestCase {
    func testSwitchingConversationsCannotRestoreOldCalendarContextOrDenial() async {
        for outcome in [CalendarLookup.meeting(MeetingInfo(title: "Old event")), .denied] {
            let coordinator = CalendarContextCoordinator()
            var current = CalendarContextCoordinator.Snapshot(conversationID: "old", notes: "", title: "New conversation",
                                                              titleState: .placeholder)
            var pending: CheckedContinuation<CalendarLookup, Never>?
            var applied: [CalendarContextCoordinator.Update] = []
            let work = coordinator.load(snapshot: { current }, lookup: {
                await withCheckedContinuation { pending = $0 }
            }, timeFormat: { _ in "unused" }, apply: { update in
                applied.append(update)
                if let notes = update.notes { current.notes = notes }
            })
            for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
            XCTAssertNotNil(pending)
            current = .init(conversationID: "new", notes: "New conversation context", title: "New title", titleState: .user)
            pending?.resume(returning: outcome)
            await work.value
            XCTAssertTrue(applied.isEmpty, "An old event or denial must not target the new conversation")
            XCTAssertEqual(current.notes, "New conversation context")
        }
    }

    func testEditingNotesWhileCalendarIsPendingKeepsTheNewText() async {
        let coordinator = CalendarContextCoordinator()
        var current = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "Original context",
                                                          title: "My title", titleState: .user)
        var pending: CheckedContinuation<CalendarLookup, Never>?
        let work = coordinator.load(snapshot: { current }, lookup: {
            await withCheckedContinuation { pending = $0 }
        }, timeFormat: { _ in "unused" }, apply: { if let notes = $0.notes { current.notes = notes } })
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        current.notes = "Text entered while waiting for Calendar"
        pending?.resume(returning: .meeting(MeetingInfo(title: "Old event")))
        await work.value
        XCTAssertEqual(current.notes, "Text entered while waiting for Calendar")
    }

    func testOlderCalendarReplyCannotReplaceANewerRequestOrClearItsLoadingState() async {
        let coordinator = CalendarContextCoordinator()
        var current = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "", title: "New conversation",
                                                          titleState: .placeholder)
        var first: CheckedContinuation<CalendarLookup, Never>?
        var second: CheckedContinuation<CalendarLookup, Never>?
        var applied: [String] = []
        func apply(_ update: CalendarContextCoordinator.Update) {
            if let notes = update.notes { current.notes = notes; applied.append(notes) }
            if let title = update.title, let state = update.titleState { current.title = title; current.titleState = state }
        }
        let old = coordinator.load(snapshot: { current }, lookup: {
            await withCheckedContinuation { first = $0 }
        }, timeFormat: { _ in "unused" }, apply: apply)
        for _ in 0..<200 where first == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(first)
        let new = coordinator.load(snapshot: { current }, lookup: {
            await withCheckedContinuation { second = $0 }
        }, timeFormat: { _ in "unused" }, apply: apply)
        for _ in 0..<200 where second == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(second)
        first?.resume(returning: .meeting(MeetingInfo(title: "Old event")))
        await old.value
        XCTAssertTrue(coordinator.isLoading, "The newer request is still waiting")
        XCTAssertTrue(applied.isEmpty)
        second?.resume(returning: .meeting(MeetingInfo(title: "New event")))
        await new.value
        XCTAssertEqual(applied, ["Meeting: New event"])
        XCTAssertEqual(current.title, "New event")
        XCTAssertFalse(coordinator.isLoading)
    }

    func testCancelBeforeExecutionNeverRequestsCalendarAccess() async {
        let coordinator = CalendarContextCoordinator()
        let current = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "", title: "My title", titleState: .user)
        var lookups = 0, publications = 0
        let work = coordinator.load(snapshot: { current }, lookup: { lookups += 1; return .denied },
                                    timeFormat: { _ in "unused" }, apply: { _ in publications += 1 })
        coordinator.cancel()
        await work.value
        XCTAssertEqual(lookups, 0)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(coordinator.isLoading)
    }

    func testCancelClearsLoadingAndIgnoresAnUncooperativeLateFailure() async {
        let coordinator = CalendarContextCoordinator()
        let current = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "", title: "My title", titleState: .user)
        var pending: CheckedContinuation<CalendarLookup, Never>?
        var publications = 0
        let work = coordinator.load(snapshot: { current }, lookup: {
            await withCheckedContinuation { pending = $0 }
        }, timeFormat: { _ in "unused" }, apply: { _ in publications += 1 })
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        coordinator.cancel()
        XCTAssertFalse(coordinator.isLoading)
        pending?.resume(returning: .failed("Obsolete local failure"))
        await work.value
        XCTAssertEqual(publications, 0)
    }

    func testCurrentEventFillsContextAndPreservesAnExplicitTitle() async {
        let event = MeetingInfo(title: "Review", start: Date(timeIntervalSince1970: 10),
                                attendees: ["Alex"], notes: "Bring the prototype")
        for titleState in [ConversationTitleState.placeholder, .automatic(words: 20), .user, .calendar] {
            let coordinator = CalendarContextCoordinator()
            let title = titleState.source == .placeholder ? "New conversation" : "Chosen title"
            let snapshot = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "", title: title,
                                                               titleState: titleState)
            var applied: [CalendarContextCoordinator.Update] = []
            let work = coordinator.load(snapshot: { snapshot }, lookup: { .meeting(event) }, timeFormat: { _ in "10:00" },
                                        apply: { applied.append($0) })
            await work.value
            XCTAssertEqual(applied.count, 1)
            XCTAssertEqual(applied.first?.conversationID, "current")
            XCTAssertEqual(applied.first?.notes, "Meeting: Review\nTime: 10:00\nAttendees: Alex\n\nEvent notes:\nBring the prototype")
            let canReplace = titleState.source == .placeholder || titleState.source == .automatic
            XCTAssertEqual(applied.first?.title, canReplace ? "Review" : nil)
            XCTAssertEqual(applied.first?.titleState, canReplace ? .calendar : nil)
            XCTAssertNil(applied.first?.error)
            XCTAssertFalse(coordinator.isLoading)
        }
    }

    func testFailureKeepsContextAndReturnsTheApplicableRecoveryMessage() async {
        for outcome in [CalendarLookup.denied, .noMeeting, .failed("Local calendar unavailable")] {
            let coordinator = CalendarContextCoordinator()
            let snapshot = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "Keep my notes",
                                                               title: "Keep my title", titleState: .user)
            var result: CalendarContextCoordinator.Update?
            let work = coordinator.load(snapshot: { snapshot }, lookup: { outcome }, timeFormat: { _ in "unused" },
                                        apply: { result = $0 })
            await work.value
            XCTAssertNil(result?.notes)
            XCTAssertNil(result?.title)
            XCTAssertEqual(result?.error, outcome.message)
            XCTAssertFalse(coordinator.isLoading)
        }
    }

    func testATitleTypedWhileCalendarIsPendingIsNotReplaced() async {
        let coordinator = CalendarContextCoordinator()
        var current = CalendarContextCoordinator.Snapshot(conversationID: "current", notes: "", title: "New conversation",
                                                          titleState: .placeholder)
        var pending: CheckedContinuation<CalendarLookup, Never>?
        var result: CalendarContextCoordinator.Update?
        let work = coordinator.load(snapshot: { current }, lookup: {
            await withCheckedContinuation { pending = $0 }
        }, timeFormat: { _ in "unused" }, apply: { result = $0 })
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        current.title = "Typed while waiting"; current.titleState = .user
        pending?.resume(returning: .meeting(MeetingInfo(title: "Calendar title")))
        await work.value
        XCTAssertEqual(result?.notes, "Meeting: Calendar title")
        XCTAssertNil(result?.title)
    }
}
