import Foundation

/// Pure decision table for the Screen Recording permission badge. The App layer gathers the raw
/// signals (CoreGraphics preflight, the prompt-free window-name heuristic, session state, the
/// ScreenCaptureKit probe result) and this resolver combines them, so the tricky precedence rules
/// are unit-testable without AppKit or CoreGraphics.
///
/// Why a resolver at all: `CGPreflightScreenCaptureAccess()` is cached for the process lifetime,
/// so it keeps reporting `false` after the user grants access in System Settings until the app is
/// relaunched. The live window-name check (reading other processes' window names, which only
/// succeeds when Screen Recording is granted and never triggers a TCC prompt) can detect that
/// grant immediately — but it is inconclusive when no titled windows happen to be on screen, so
/// the signals must be weighed carefully rather than trusted individually.
public enum ScreenRecordingStatus {
    /// Mirror of the app-facing permission states, kept AppKit-free so Core stays pure.
    public enum Grant: Sendable, Equatable {
        case granted, denied, notDetermined, unverified
    }

    /// The resolved badge state plus whether the UI should steer the user to relaunch the app
    /// (the grant is live in TCC but this process may need a restart before capture works).
    public struct Resolution: Sendable, Equatable {
        public let status: Grant
        public let needsRelaunchHint: Bool

        public init(status: Grant, needsRelaunchHint: Bool) {
            self.status = status
            self.needsRelaunchHint = needsRelaunchHint
        }
    }

    /// Combines the four Screen Recording signals in strength order:
    /// 1. `probeConfirmed` (ScreenCaptureKit succeeded in THIS process) always wins — capture
    ///    demonstrably works, so no relaunch hint either.
    /// 2. `liveNameCheck == true` proves the TCC grant is live; when the cached `preflight` still
    ///    says `false`, this process may need a relaunch before capture starts, so the hint is set.
    /// 3. `preflight == true` is the OS's own answer for this process — a negative name check is
    ///    a weak signal (windows may legitimately all be untitled) and must not downgrade it.
    /// 4. Negative or inconclusive checks cannot distinguish an absent grant from a stale
    ///    process/identity. Clicking Grant is not evidence of denial: report unverified.
    public static func resolve(
        preflight: Bool,
        liveNameCheck: Bool?,
        requestedThisSession: Bool,
        probeConfirmed: Bool
    ) -> Resolution {
        if probeConfirmed {
            return Resolution(status: .granted, needsRelaunchHint: false)
        }
        if liveNameCheck == true {
            return Resolution(status: .granted, needsRelaunchHint: !preflight)
        }
        if preflight {
            return Resolution(status: .granted, needsRelaunchHint: false)
        }
        return Resolution(status: .unverified,
                          needsRelaunchHint: false)
    }
}
