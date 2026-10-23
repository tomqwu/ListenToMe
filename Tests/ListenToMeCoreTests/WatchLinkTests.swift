import XCTest
@testable import ListenToMeCore

/// The wire protocol between the Apple Watch remote and the iPhone (issue #181).
final class WatchLinkTests: XCTestCase {
    func testCommandRoundTripsAndCarriesTheProtocolVersion() throws {
        for command in WatchCommand.allCases {
            let message = WatchLink.message(for: command)
            XCTAssertEqual(message["v"] as? Int, 1)
            XCTAssertEqual(try WatchLink.command(from: message), command)
        }
    }

    func testUnknownVersionAndMalformedMessagesAreRejected() {
        XCTAssertThrowsError(try WatchLink.command(from: ["v": 2, "cmd": "start"])) {
            XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(2)) }
        XCTAssertThrowsError(try WatchLink.command(from: ["cmd": "start"])) {
            XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(nil)) }
        XCTAssertThrowsError(try WatchLink.command(from: ["v": 1, "cmd": "erase"]))
        XCTAssertThrowsError(try WatchLink.command(from: ["v": 1]))
    }

    func testEveryReplyRoundTrips() throws {
        let status = PhoneRecorderStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                         title: "Standup", lastStopReason: nil)
        for reply in [WatchReply.accepted(status), .openPhoneApp, .busy("Stopping on iPhone"), .unsupportedVersion] {
            let message = WatchLink.message(for: reply)
            XCTAssertEqual(message["v"] as? Int, 1)
            XCTAssertEqual(try WatchLink.reply(from: message), reply)
        }
    }

    func testMalformedRepliesAreRejected() {
        XCTAssertThrowsError(try WatchLink.reply(from: ["v": 2, "reply": "openPhoneApp"])) {
            XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(2)) }
        XCTAssertThrowsError(try WatchLink.reply(from: ["v": 1]))
        XCTAssertThrowsError(try WatchLink.reply(from: ["v": 1, "reply": "explode"]))
        XCTAssertThrowsError(try WatchLink.reply(from: ["v": 1, "reply": "busy"]))
        XCTAssertThrowsError(try WatchLink.reply(from: ["v": 1, "reply": "accepted"]))
        XCTAssertThrowsError(try WatchLink.reply(from: ["v": 1, "reply": "accepted", "status": ["state": "flying"]]))
    }

    func testPhoneStatusContextRoundTripsAndIgnoresOtherVersions() {
        let status = PhoneRecorderStatus(state: .idle, startedAt: nil, title: "A", lastStopReason: .background)
        XCTAssertEqual(WatchLink.phoneStatus(fromContext: WatchLink.context(for: status)), status)
        XCTAssertNil(WatchLink.phoneStatus(fromContext: ["v": 2, "phone": [:]]))
        XCTAssertNil(WatchLink.phoneStatus(fromContext: [:]))
    }

    func testEveryPhoneStatusFieldRoundTrips() {
        for state in [PhoneRecorderState.idle, .preparing, .recording, .stopping] {
            for reason in [nil, PhoneStopReason.user, .interruption, .routeLost, .background] {
                let status = PhoneRecorderStatus(state: state, startedAt: Date(timeIntervalSince1970: 1_234.5),
                                                 title: "Weekly", lastStopReason: reason)
                XCTAssertEqual(WatchLink.phoneStatus(fromContext: WatchLink.context(for: status)), status)
            }
        }
        XCTAssertNil(WatchLink.phoneStatus(fromContext: ["v": 1, "phone": ["state": "flying"]]))
    }

    func testOnlyPropertyListTypesCrossTheLink() throws {
        let status = PhoneRecorderStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                         title: "Standup", lastStopReason: .user)
        let payloads: [[String: Any]] = [WatchLink.message(for: .start), WatchLink.message(for: .accepted(status)),
                                         WatchLink.message(for: .busy("x")), WatchLink.context(for: status)]
        for payload in payloads {
            XCTAssertTrue(PropertyListSerialization.propertyList(payload, isValidFor: .binary), "\(payload)")
        }
    }

    func testElapsedText() {
        XCTAssertEqual(WatchLink.elapsedText(0), "00:00")
        XCTAssertEqual(WatchLink.elapsedText(65.9), "01:05")
        XCTAssertEqual(WatchLink.elapsedText(3_725), "1:02:05")
        XCTAssertEqual(WatchLink.elapsedText(-3), "00:00")
        XCTAssertEqual(WatchLink.elapsedText(.nan), "00:00")
        XCTAssertEqual(WatchLink.elapsedText(.infinity), "00:00")
    }

    func testRemoteTextPrecedence() {
        let now = Date(timeIntervalSince1970: 1_065)
        let recording = PhoneRecorderStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                            title: "A", lastStopReason: nil)
        XCTAssertEqual(WatchRemoteText.line(status: recording, reachable: true, lastReply: nil, now: now),
                       "iPhone is recording · 01:05")
        XCTAssertEqual(WatchRemoteText.line(status: recording, reachable: false, lastReply: nil, now: now),
                       "iPhone not reachable")
        XCTAssertEqual(WatchRemoteText.line(status: nil, reachable: true, lastReply: .openPhoneApp, now: now),
                       "Open ListenToMe on your iPhone to record")
        XCTAssertEqual(WatchRemoteText.line(status: nil, reachable: true, lastReply: .unsupportedVersion, now: now),
                       "Update ListenToMe on your iPhone and Apple Watch")
        let stopped = PhoneRecorderStatus(state: .idle, startedAt: nil, title: "A", lastStopReason: .background)
        XCTAssertEqual(WatchRemoteText.line(status: stopped, reachable: true, lastReply: nil, now: now),
                       "Stopped: ListenToMe left the foreground on iPhone")
    }

    func testRemoteTextForEveryOtherState() {
        let now = Date(timeIntervalSince1970: 1_065)
        func line(_ state: PhoneRecorderState, _ reason: PhoneStopReason? = nil,
                  reply: WatchReply? = nil) -> String {
            WatchRemoteText.line(status: PhoneRecorderStatus(state: state, startedAt: nil, title: "A",
                                                             lastStopReason: reason),
                                 reachable: true, lastReply: reply, now: now)
        }
        XCTAssertEqual(line(.idle, reply: .busy("Generating a summary on iPhone")), "Generating a summary on iPhone")
        XCTAssertEqual(line(.preparing), "Starting on iPhone…")
        XCTAssertEqual(line(.stopping), "Stopping on iPhone")
        XCTAssertEqual(line(.idle), "Ready")
        XCTAssertEqual(line(.idle, .user), "Ready")
        XCTAssertEqual(line(.recording), "iPhone is recording · 00:00")
        let accepted = PhoneRecorderStatus(state: .preparing, startedAt: nil, title: "A", lastStopReason: nil)
        XCTAssertEqual(line(.idle, reply: .accepted(accepted)), "Ready")
        XCTAssertEqual(WatchRemoteText.line(status: nil, reachable: true, lastReply: nil, now: now), "Ready")
    }
}
