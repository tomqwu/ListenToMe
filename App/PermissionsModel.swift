import Foundation
import Observation
import AVFoundation
import Speech
import CoreGraphics
import ScreenCaptureKit
import ApplicationServices
import AppKit

@MainActor
@Observable
final class PermissionsModel {
    enum Status { case granted, denied, notDetermined }

    private(set) var microphone: Status = .notDetermined
    private(set) var speech: Status = .notDetermined
    private(set) var screenRecording: Status = .notDetermined
    private(set) var accessibility: Status = .notDetermined

    private var screenRequested = false
    private var accessibilityRequested = false
    /// Set once a live ScreenCaptureKit probe confirms the grant, so later `refresh()` calls don't
    /// downgrade it from the stale (process-cached) CoreGraphics preflight value.
    private var screenProbedGranted = false

    /// The three permissions required for core capture+transcription (Accessibility is optional).
    var allRequiredGranted: Bool {
        microphone == .granted && speech == .granted && screenRecording == .granted
    }

    func refresh() {
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.mapSpeech(SFSpeechRecognizer.authorizationStatus())
        if screenProbedGranted {
            screenRecording = .granted   // a live probe already confirmed it; don't downgrade
        } else {
            screenRecording = CGPreflightScreenCaptureAccess()
                ? .granted : (screenRequested ? .denied : .notDetermined)
        }
        accessibility = AXIsProcessTrusted()
            ? .granted : (accessibilityRequested ? .denied : .notDetermined)
        // CGPreflightScreenCaptureAccess() is cached for the process lifetime, so it reports a
        // stale `false` after the user enables Screen Recording without relaunching. Once the user
        // has engaged the Grant flow, confirm the real grant with a live ScreenCaptureKit query and
        // upgrade the badge when it actually works. Gated on `screenRequested` so the probe (which
        // can surface the one-time system prompt) never fires before the user clicks Grant.
        if screenRecording != .granted, screenRequested { probeScreenRecording() }
    }

    /// Asynchronously verifies Screen Recording access by querying ScreenCaptureKit (which reflects
    /// the live grant, unlike the cached preflight). Only upgrades the status to `.granted`.
    private func probeScreenRecording() {
        Task { [weak self] in
            guard await Self.canScreenCapture() else { return }
            self?.screenProbedGranted = true
            self?.screenRecording = .granted
        }
    }

    nonisolated private static func canScreenCapture() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
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
        // Registers the app in the Screen Recording list and shows the one-time system prompt.
        // macOS only ever presents that prompt once, so if access isn't already effective, send the
        // user straight to the Screen Recording pane to toggle ListenToMe on (then Quit & Reopen).
        if !CGRequestScreenCaptureAccess() {
            openSettings("Privacy_ScreenCapture")
        }
        refresh()
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
