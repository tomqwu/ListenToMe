import XCTest
@testable import ListenToMeCore

final class WatchReadinessTests: XCTestCase {
    func testUnreachableOrIncompatiblePhoneCannotOfferRemoteStart() {
        let ready = status(.idle, ready: true)
        XCTAssertFalse(WatchReadiness.remote(status: ready, reachable: false, lastReply: nil).canRun)
        XCTAssertFalse(WatchReadiness.remote(status: ready, reachable: true, lastReply: .unsupportedVersion).canRun)
        XCTAssertFalse(WatchReadiness.remote(status: ready, reachable: true, lastReply: .openPhoneApp).canRun)
        XCTAssertTrue(WatchReadiness.remote(status: ready, reachable: true, lastReply: nil).canRun)
    }

    func testUnknownOrUnsupportedPhoneSpeechIsExplainedAndDoesNotBlockStop() {
        XCTAssertFalse(WatchReadiness.remote(status: nil, reachable: true, lastReply: nil).canRun)
        XCTAssertFalse(WatchReadiness.remote(status: status(.idle, ready: nil), reachable: true, lastReply: nil).canRun)
        let unavailable = status(.idle, ready: false)
        let blocked = WatchReadiness.remote(status: unavailable, reachable: true, lastReply: nil)
        XCTAssertFalse(blocked.canRun)
        XCTAssertEqual(blocked.reason, "Choose a supported language on iPhone.")
        for state: PhoneRecorderState in [.preparing, .recording] {
            XCTAssertTrue(WatchReadiness.remote(status: status(state, ready: false), reachable: true, lastReply: nil).canRun,
                          "Stop must remain available after start capability changes")
        }
        XCTAssertFalse(WatchReadiness.remote(status: status(.stopping, ready: true), reachable: true, lastReply: nil).canRun)
    }

    func testPhoneCapabilityRoundTripsWithoutTranscriptOrRemoteRoutingInformation() throws {
        let original = status(.idle, ready: false)
        let context = WatchLink.context(for: original)
        XCTAssertEqual(WatchLink.phoneStatus(fromContext: context), original)
        XCTAssertEqual(try WatchLink.reply(from: WatchLink.message(for: .accepted(original))), .accepted(original))
        let legacy: [String: Any] = ["v": 1, "phone": ["state": "idle", "title": "Legacy"]]
        let decoded = try XCTUnwrap(WatchLink.phoneStatus(fromContext: legacy))
        XCTAssertNil(decoded.recordingReady)
        XCTAssertFalse(WatchReadiness.remote(status: decoded, reachable: true, lastReply: nil).canRun)
    }

    func testWatchLocalRecordingNeedsPermissionAndResourcesButNotPhoneConnectivity() {
        let denied = WatchReadiness.local(microphoneDenied: true, battery: 1, freeBytes: Int64.max)
        XCTAssertFalse(denied.canRun)
        XCTAssertNotNil(denied.setupAction)
        XCTAssertFalse(WatchReadiness.local(microphoneDenied: false, battery: 0.01, freeBytes: Int64.max).canRun)
        XCTAssertFalse(WatchReadiness.local(microphoneDenied: false, battery: 1, freeBytes: 0).canRun)
        XCTAssertTrue(WatchReadiness.local(microphoneDenied: false, battery: -1, freeBytes: nil).canRun)
    }

    private func status(_ state: PhoneRecorderState, ready: Bool?) -> PhoneRecorderStatus {
        PhoneRecorderStatus(state: state, startedAt: nil, title: "Conversation", lastStopReason: nil,
                            recordingReady: ready, recordingUnavailableReason: "Choose a supported language on iPhone.")
    }
}
