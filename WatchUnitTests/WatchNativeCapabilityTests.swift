import XCTest
@testable import ListenToMeWatch

@MainActor
final class WatchNativeCapabilityTests: XCTestCase {
    // Baseline adoption; actual native client control state and action, no historical red claimed.
    func testOfflineNativeClientRefusesRemoteStart() async {
        let link = WatchLinkClient()
        XCTAssertFalse(link.isReachable)
        XCTAssertFalse(link.remoteAvailability.canRun)
        XCTAssertEqual(link.remoteAvailability.reason, "iPhone not reachable")
        await link.send(.start)
        XCTAssertFalse(link.isSending)
        XCTAssertNil(link.phoneStatus)
        XCTAssertNil(link.lastReply)
    }

    // Existing refusal behavior adopted into native coverage; no historical red claimed.
    func testLocalUnavailableProfilesRefuseBeforePermissionOrCapture() async {
        for snapshot in [
            WatchRecorder.CapabilitySnapshot(microphoneDenied: true, battery: 1, freeBytes: Int64.max),
            .init(microphoneDenied: false, battery: 0.01, freeBytes: Int64.max),
            .init(microphoneDenied: false, battery: 1, freeBytes: 0),
        ] {
            var permissions = 0
            var captures = 0
            let recorder = WatchRecorder(makeCapture: {
                captures += 1
                return WatchEngineCapture()
            }, capabilitySnapshot: { snapshot }, requestPermission: {
                permissions += 1
                throw WatchRecorderError.unavailable("Unexpected permission request")
            })
            XCTAssertFalse(recorder.availability.canRun)
            XCTAssertNotNil(recorder.availability.reason)
            do {
                try await recorder.start()
                XCTFail("Unavailable recording started")
            } catch let error as WatchRecorderError {
                guard case .blocked(let reason) = error else { return XCTFail("Wrong refusal: \(error)") }
                XCTAssertEqual(reason, recorder.availability.reason)
            } catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(permissions, 0)
            XCTAssertEqual(captures, 0)
            XCTAssertFalse(recorder.isRecording)
        }
    }

    func testRemoteReadinessRefusesStartButKeepsStopAvailable() async {
        var sent: [WatchCommand] = []
        let link = WatchLinkClient(sendMessage: { message, reply, _ in
            guard let command = try? WatchLink.command(from: message) else {
                return XCTFail("Invalid native command")
            }
            XCTAssertEqual(Set(message.keys), Set(["v", "cmd"]))
            sent.append(command)
            let state: PhoneRecorderState = command == .start ? .preparing : .idle
            reply(WatchLink.message(for: .accepted(PhoneRecorderStatus(
                state: state, startedAt: nil, title: "", lastStopReason: nil, recordingReady: false, recordingUnavailableReason: "Speech unavailable")),
                stamp: Double(10 + sent.count)))
        })
        let unavailable = PhoneRecorderStatus(state: .idle, startedAt: nil, title: "", lastStopReason: nil, recordingReady: false,
                                             recordingUnavailableReason: "Speech unavailable")
        link.apply(context: unavailable, stamp: 1, reachable: true)
        XCTAssertFalse(link.remoteAvailability.canRun)
        XCTAssertEqual(link.remoteAvailability.reason, "Speech unavailable")
        await link.send(.start)
        XCTAssertTrue(sent.isEmpty)
        link.apply(context: PhoneRecorderStatus(state: .idle, startedAt: nil, title: "", lastStopReason: nil, recordingReady: true), stamp: 2, reachable: true)
        XCTAssertTrue(link.remoteAvailability.canRun)
        await link.send(.start)
        XCTAssertEqual(sent, [.start])
        XCTAssertEqual(link.phoneStatus?.state, .preparing)
        XCTAssertTrue(link.remoteAvailability.canRun, "Losing Start capability must not disable Stop")
        await link.send(.stop)
        XCTAssertEqual(sent, [.start, .stop])
        XCTAssertFalse(link.remoteAvailability.canRun)
        XCTAssertFalse(link.isSending)
    }

}
