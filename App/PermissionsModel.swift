import Foundation
import Observation
import AVFoundation
import Speech
import CoreGraphics
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

    /// The three permissions required for core capture+transcription (Accessibility is optional).
    var allRequiredGranted: Bool {
        microphone == .granted && speech == .granted && screenRecording == .granted
    }

    func refresh() {
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.mapSpeech(SFSpeechRecognizer.authorizationStatus())
        screenRecording = CGPreflightScreenCaptureAccess()
            ? .granted : (screenRequested ? .denied : .notDetermined)
        accessibility = AXIsProcessTrusted()
            ? .granted : (accessibilityRequested ? .denied : .notDetermined)
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.refresh() }
        }
    }
    func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in
            Task { @MainActor in self.refresh() }
        }
    }
    func requestScreenRecording() {
        screenRequested = true
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }
    func requestAccessibility() {
        accessibilityRequested = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refresh()
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
