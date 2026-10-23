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

    // MARK: Status ordering

    func testStatusStampsTravelWithContextsAndReplies() throws {
        let status = PhoneRecorderStatus(state: .recording, startedAt: nil, title: "A", lastStopReason: nil)
        let context = WatchLink.context(for: status, stamp: 1_234.5)
        XCTAssertEqual(WatchLink.phoneStatus(fromContext: context), status)
        XCTAssertEqual(WatchLink.stamp(from: context), 1_234.5)
        let reply = WatchLink.message(for: .accepted(status), stamp: 99)
        XCTAssertEqual(try WatchLink.reply(from: reply), .accepted(status))
        XCTAssertEqual(WatchLink.stamp(from: reply), 99)
        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
        XCTAssertNil(WatchLink.stamp(from: WatchLink.context(for: status)), "An older phone build sends none")
        XCTAssertNil(WatchLink.stamp(from: ["at": "yesterday"]))
        XCTAssertNil(WatchLink.stamp(from: ["at": Double.nan]))
    }

    func testTrackerNeverLetsAnOlderStatusOverwriteANewerOne() {
        func status(_ state: PhoneRecorderState) -> PhoneRecorderStatus {
            PhoneRecorderStatus(state: state, startedAt: nil, title: "A", lastStopReason: nil)
        }
        var tracker = PhoneStatusTracker()
        XCTAssertNil(tracker.status)
        XCTAssertTrue(tracker.apply(status(.recording), stamp: 20))
        // The reply to Start, made before the recorder was running, arrives after the context.
        XCTAssertFalse(tracker.apply(status(.preparing), stamp: 10))
        XCTAssertEqual(tracker.status, status(.recording))
        XCTAssertTrue(tracker.apply(status(.recording), stamp: 20), "The same status again is not older")
        XCTAssertTrue(tracker.apply(status(.idle), stamp: 30))
        XCTAssertEqual(tracker.stamp, 30)
        XCTAssertTrue(tracker.apply(status(.stopping), stamp: nil), "An unstamped status is always shown")
        XCTAssertEqual(tracker.status, status(.stopping))
        XCTAssertEqual(tracker.stamp, 30)
        // Replies that carry no status (busy, open the iPhone app) are judged by the same stamp.
        XCTAssertFalse(tracker.isCurrent(29))
        XCTAssertTrue(tracker.isCurrent(30))
        XCTAssertTrue(tracker.isCurrent(nil))
        XCTAssertTrue(PhoneStatusTracker().isCurrent(1))
    }

    // MARK: Chunk metadata and end marker (Slice 2)

    private let recordingID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    private func chunk(index: Int = 3, startOffset: TimeInterval = 900, duration: TimeInterval = 300,
                       isLast: Bool = false) -> WatchChunkMetadata {
        WatchChunkMetadata(recordingID: recordingID, index: index, startOffset: startOffset, duration: duration,
                           isLast: isLast, startedAt: Date(timeIntervalSince1970: 1_700_000_000.5), watchBuild: "28")
    }

    func testChunkMetadataRoundTrips() throws {
        for value in [chunk(), chunk(index: 0, startOffset: 0, duration: 12.5, isLast: true),
                      chunk(index: WatchChunkMetadata.maximumIndex, duration: 599.9)] {
            let metadata = value.transferMetadata
            XCTAssertEqual(metadata["v"] as? Int, 1)
            XCTAssertEqual(metadata["recordingID"] as? String, recordingID.uuidString)
            XCTAssertTrue(PropertyListSerialization.propertyList(metadata, isValidFor: .binary))
            XCTAssertEqual(try WatchChunkMetadata(transferMetadata: metadata), value)
            // What WatchConnectivity hands back: the same dictionary after a property-list round trip.
            let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            let decoded = try XCTUnwrap(plist as? [String: Any])
            XCTAssertEqual(try WatchChunkMetadata(transferMetadata: decoded), value)
        }
        XCTAssertEqual(WatchChunkMetadata.maximumIndex, 999)
        XCTAssertEqual(WatchChunkMetadata.maximumDuration, 600)
        XCTAssertEqual(WatchChunkMetadata.maximumFileBytes, 10_000_000)
        let json = try JSONEncoder().encode(chunk())
        XCTAssertEqual(try JSONDecoder().decode(WatchChunkMetadata.self, from: json), chunk())
    }

    func testChunkMetadataRejectsOutOfRangeValues() {
        let valid = chunk().transferMetadata
        func rejects(_ key: String, _ value: Any?, line: UInt = #line) {
            var metadata = valid
            metadata[key] = value
            XCTAssertThrowsError(try WatchChunkMetadata(transferMetadata: metadata),
                                 "\(key)=\(String(describing: value))", line: line)
        }
        rejects("index", 1_000)
        rejects("index", -1)
        rejects("duration", 0.0)
        rejects("duration", 600.0)
        rejects("duration", -5.0)
        rejects("duration", Double.nan)
        rejects("startOffset", -1.0)
        rejects("startOffset", Double.infinity)
        rejects("startOffset", Double.nan)
        rejects("startedAt", Double.nan)
        rejects("recordingID", "not-a-uuid")
        rejects("recordingID", 42)
        rejects("isLast", "yes")
        rejects("watchBuild", nil)
        rejects("index", nil)
        var future = valid
        future["v"] = 2
        XCTAssertThrowsError(try WatchChunkMetadata(transferMetadata: future)) {
            XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(2)) }
    }

    func testChunkMetadataIgnoresPathLikeKeys() throws {
        var metadata = chunk().transferMetadata
        metadata["path"] = "../../x"
        metadata["fileName"] = "/etc/passwd"
        XCTAssertEqual(try WatchChunkMetadata(transferMetadata: metadata), chunk())
        // Nothing the watch sends can name a file: no field of the type holds free-form text except
        // the build number, which is never used as a path.
        let labels = Mirror(reflecting: chunk()).children.compactMap(\.label)
        XCTAssertEqual(Set(labels), ["recordingID", "index", "startOffset", "duration", "isLast", "startedAt",
                                     "watchBuild"])
    }

    func testRecordingEndRoundTripsAndRejectsVersion2() throws {
        let end = WatchRecordingEnd(recordingID: recordingID, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                    lastIndex: 4, unexpected: true)
        let info = end.userInfo
        XCTAssertEqual(info["v"] as? Int, 1)
        XCTAssertEqual(info["end"] as? String, recordingID.uuidString)
        XCTAssertTrue(PropertyListSerialization.propertyList(info, isValidFor: .binary))
        XCTAssertEqual(try WatchRecordingEnd(userInfo: info), end)
        var future = info
        future["v"] = 2
        XCTAssertThrowsError(try WatchRecordingEnd(userInfo: future)) {
            XCTAssertEqual($0 as? WatchLinkError, .unsupportedVersion(2)) }
        for (key, value) in [("end", "x"), ("lastIndex", "4"), ("lastIndex", 1_000), ("lastIndex", -1),
                             ("unexpected", "no"), ("startedAt", "now")] as [(String, Any)] {
            var broken = info
            broken[key] = value
            XCTAssertThrowsError(try WatchRecordingEnd(userInfo: broken), key)
        }
        // A chunk's metadata is not an end marker.
        XCTAssertThrowsError(try WatchRecordingEnd(userInfo: chunk().transferMetadata))
    }
}
