import Foundation
import Observation
import AVFoundation
import Speech
import CoreGraphics
import ScreenCaptureKit
import ApplicationServices
import AppKit
import ListenToMeCore

@MainActor
@Observable
final class PermissionsModel {
    enum Status { case granted, denied, notDetermined, unverified }

    private(set) var microphone: Status = .notDetermined
    private(set) var speech: Status = .notDetermined
    private(set) var screenRecording: Status = .notDetermined
    private(set) var accessibility: Status = .notDetermined
    /// True when the Screen Recording grant is live in TCC but this process was launched before it
    /// (stale preflight): the badge shows Granted, and the UI should steer the user to Quit & Reopen
    /// so capture can actually use the grant.
    private(set) var screenNeedsRelaunchHint = false

    private var screenRequested = UserDefaults.standard.bool(forKey: "screenVerificationRequested")
    private var screenProbeInFlight = false
    private(set) var screenVerificationMessage: String?
    private var accessibilityRequested = false
    /// Set once a live ScreenCaptureKit probe confirms the grant, so later `refresh()` calls don't
    /// downgrade it from the stale (process-cached) CoreGraphics preflight value.
    private var screenProbedGranted = false
    /// Set once the window-name check has proven the grant live. Sticky for the same reason as
    /// `screenProbedGranted`: the check depends on which windows share the current Space, so a
    /// later inconclusive/negative sample (e.g. an empty fullscreen Space) must not flap the badge
    /// back to Denied after the grant was already observed. A mid-session revoke leaves access
    /// effective until relaunch anyway, so remembering a past `true` never overstates access.
    private var screenLiveNameConfirmed = false

    /// The three permissions required for core capture+transcription (Accessibility is optional).
    var allRequiredGranted: Bool {
        microphone == .granted && speech == .granted && screenRecording == .granted
    }

    func refresh() {
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.mapSpeech(SFSpeechRecognizer.authorizationStatus())
        // CGPreflightScreenCaptureAccess() is cached for the process lifetime, so it reports a
        // stale `false` after the user enables Screen Recording without relaunching. The resolver
        // weighs it against the prompt-free window-name check (safe on every refresh) and the
        // ScreenCaptureKit probe result; see ScreenRecordingStatus for the precedence rules.
        if Self.liveScreenRecordingNameCheck() == true { screenLiveNameConfirmed = true }
        let resolution = ScreenRecordingStatus.resolve(
            preflight: CGPreflightScreenCaptureAccess(),
            liveNameCheck: screenLiveNameConfirmed ? true : nil,
            requestedThisSession: screenRequested,
            probeConfirmed: screenProbedGranted
        )
        screenRecording = Self.map(resolution.status)
        screenNeedsRelaunchHint = resolution.needsRelaunchHint
        accessibility = AXIsProcessTrusted()
            ? .granted : (accessibilityRequested ? .denied : .notDetermined)
        // Once the user has engaged the Grant flow, confirm the real grant with a live
        // ScreenCaptureKit query and upgrade the badge when it actually works. Gated on
        // `screenRequested` so the probe (which can surface the one-time system prompt) never
        // fires before the user clicks Grant. Also probe in the granted-with-hint state (the name
        // check proved the grant live, so SCShareableContent cannot prompt): on success the hint
        // clears, sparing the user a Quit & Reopen that capture doesn't actually need.
        if (screenRecording != .granted && screenRequested) || screenNeedsRelaunchHint {
            probeScreenRecording()
        }
    }

    /// Prompt-free live check for Screen Recording: `kCGWindowName` of OTHER processes' windows is
    /// only readable when the grant is live in TCC, and reading it never triggers the system
    /// prompt — unlike SCShareableContent, so this is safe to run on every `refresh()`. Considers
    /// only on-screen, layer-0 windows owned by other pids; returns `true` when any has a
    /// non-empty name, `nil` (inconclusive) when there are no candidate windows at all, and
    /// `false` when candidates exist but no name is readable (a weak signal — windows may
    /// legitimately be untitled — which the resolver never lets override a positive preflight).
    nonisolated private static func liveScreenRecordingNameCheck() -> Bool? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownPid = getpid()
        var sawCandidate = false
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            sawCandidate = true
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty { return true }
        }
        return sawCandidate ? false : nil
    }

    /// Query the same framework used for system audio, only after an explicit request or
    /// positive evidence of an existing grant. Coalesce activation/refresh notifications.
    private func probeScreenRecording() {
        guard !screenProbeInFlight else { return }
        screenProbeInFlight = true
        screenVerificationMessage = "Checking access…"
        Task { [weak self] in
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let self else { return }
                screenProbeInFlight = false
                screenProbedGranted = true
                screenRecording = .granted
                screenNeedsRelaunchHint = false
                screenVerificationMessage = nil
            } catch {
                guard let self else { return }
                screenProbeInFlight = false
                let failure = error as NSError
                // Enumeration can fail for reasons other than permission. Do not label every
                // error Denied, and retain the error code so support can distinguish failures.
                screenProbedGranted = false
                screenRecording = .unverified
                screenVerificationMessage = "Could not verify access (\(failure.domain), \(failure.code)). " +
                    "If ListenToMe is already enabled in System Settings, quit and reopen this app, then Recheck."
            }
        }
    }

    nonisolated func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    nonisolated func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func requestScreenRecording() {
        screenRequested = true
        UserDefaults.standard.set(true, forKey: "screenVerificationRequested")
        // ScreenCaptureKit performs the actual check/request. A false CoreGraphics return
        // used to send already-authorized users to Settings and briefly label them Denied.
        probeScreenRecording()
    }
    func requestAccessibility() {
        accessibilityRequested = true
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        // Same one-time-prompt limitation: open the pane directly when not yet trusted.
        if !trusted {
            openSettings("Privacy_Accessibility")
        }
        refresh()
    }

    /// Relaunches the app — required for macOS to recognize a newly-granted Screen Recording
    /// permission (`CGPreflightScreenCaptureAccess` only updates after a restart).
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ s: ScreenRecordingStatus.Grant) -> Status {
        switch s {
        case .granted: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .unverified: return .unverified
        }
    }
    private static func map(_ s: AVAuthorizationStatus) -> Status {
        switch s {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
    private static func mapSpeech(_ s: SFSpeechRecognizerAuthorizationStatus) -> Status {
        switch s {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}
