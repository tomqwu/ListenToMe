import XCTest
@testable import ListenToMeCore

final class ScreenRecordingStatusTests: XCTestCase {
    private typealias SRS = ScreenRecordingStatus

    // MARK: - Rule 1: a confirmed ScreenCaptureKit probe always wins

    func testProbeConfirmedWinsOverAllNegativeSignals() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: false, requestedThisSession: true, probeConfirmed: true
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: false))
    }

    func testProbeConfirmedWinsWithInconclusiveLiveCheck() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: nil, requestedThisSession: false, probeConfirmed: true
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: false))
    }

    func testProbeConfirmedNeverCarriesRelaunchHintEvenWhenPreflightIsStale() {
        // The probe proved capture works in THIS process, so no relaunch is needed even
        // though the cached preflight still says false.
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: true, requestedThisSession: true, probeConfirmed: true
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: false))
    }

    // MARK: - Rule 2: readable window names while preflight is stale → granted + relaunch hint

    func testLiveNamesWithStalePreflightGrantWithRelaunchHint() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: true, requestedThisSession: false, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: true))
    }

    func testLiveNamesWithStalePreflightGrantRegardlessOfRequestedThisSession() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: true, requestedThisSession: true, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: true))
    }

    func testLiveNamesWithFreshPreflightGrantWithoutHint() {
        // Both signals agree the grant is effective for this process — no relaunch needed.
        let resolution = SRS.resolve(
            preflight: true, liveNameCheck: true, requestedThisSession: false, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: false))
    }

    // MARK: - Rule 3: candidates existed but no names readable → not granted (weak signal)

    func testNegativeLiveCheckAfterRequestThisSessionIsDenied() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: false, requestedThisSession: true, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .denied, needsRelaunchHint: false))
    }

    func testNegativeLiveCheckBeforeAnyRequestIsNotDetermined() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: false, requestedThisSession: false, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .notDetermined, needsRelaunchHint: false))
    }

    func testWeakNegativeLiveCheckDoesNotDowngradeFreshPreflight() {
        // Windows may legitimately all have empty names even when access is granted, so a
        // negative name check must never override the OS's own positive preflight answer.
        let resolution = SRS.resolve(
            preflight: true, liveNameCheck: false, requestedThisSession: true, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: false))
    }

    // MARK: - Rule 4: inconclusive live check (nil) → today's preflight/requested fallback

    func testInconclusiveLiveCheckFallsBackToPreflightGranted() {
        let resolution = SRS.resolve(
            preflight: true, liveNameCheck: nil, requestedThisSession: false, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .granted, needsRelaunchHint: false))
    }

    func testInconclusiveLiveCheckFallsBackToDeniedWhenRequested() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: nil, requestedThisSession: true, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .denied, needsRelaunchHint: false))
    }

    func testInconclusiveLiveCheckFallsBackToNotDeterminedWhenNotRequested() {
        let resolution = SRS.resolve(
            preflight: false, liveNameCheck: nil, requestedThisSession: false, probeConfirmed: false
        )
        XCTAssertEqual(resolution, SRS.Resolution(status: .notDetermined, needsRelaunchHint: false))
    }

    // MARK: - Invariant: the relaunch hint exists ONLY for the live-upgrade-over-stale-preflight case

    func testRelaunchHintOnlySetWhenLiveCheckUpgradesStalePreflight() {
        for preflight in [false, true] {
            for liveNameCheck in [nil, false, true] as [Bool?] {
                for requested in [false, true] {
                    for probed in [false, true] {
                        let resolution = SRS.resolve(
                            preflight: preflight, liveNameCheck: liveNameCheck,
                            requestedThisSession: requested, probeConfirmed: probed
                        )
                        let expected = !probed && !preflight && liveNameCheck == true
                        XCTAssertEqual(
                            resolution.needsRelaunchHint, expected,
                            "hint mismatch for preflight=\(preflight) live=\(String(describing: liveNameCheck)) "
                                + "requested=\(requested) probed=\(probed)"
                        )
                        if resolution.needsRelaunchHint {
                            XCTAssertEqual(resolution.status, .granted,
                                           "the relaunch hint only makes sense on a granted status")
                        }
                    }
                }
            }
        }
    }
}
