import Foundation

/// Shared by the native Watch controls and their headless acceptance tests.
public enum WatchReadiness {
    public static func remote(status: PhoneRecorderStatus?, reachable: Bool, lastReply: WatchReply?) -> FeatureAvailability {
        guard reachable else { return .temporarilyUnavailable(reason: "iPhone not reachable") }
        switch lastReply {
        case .unsupportedVersion:
            return .unsupported(reason: "Update ListenToMe on your iPhone and Apple Watch")
        case .openPhoneApp:
            return .setupRequired(reason: "Open ListenToMe on your iPhone to record", action: "Open iPhone app")
        case .busy(let reason): return .temporarilyUnavailable(reason: reason)
        case .accepted, nil: break
        }
        guard let status else { return .temporarilyUnavailable(reason: "Waiting for iPhone recording status") }
        // This action is Stop. A lost Start capability must not prevent stopping a live recording.
        if status.state == .recording || status.state == .preparing { return .ready }
        if status.state == .stopping { return .temporarilyUnavailable(reason: "Stopping on iPhone") }
        guard let ready = status.recordingReady else {
            return .temporarilyUnavailable(reason: "Open the updated ListenToMe app on iPhone to check recording support")
        }
        guard ready else {
            return .setupRequired(reason: status.recordingUnavailableReason ?? "Check recording settings on iPhone",
                                  action: "Open iPhone app")
        }
        return .ready
    }

    /// An undetermined microphone permission is requested only after the user's Record tap.
    /// Connectivity is intentionally absent: local capture works offline and the outbox syncs later.
    public static func local(microphoneDenied: Bool, battery: Float, freeBytes: Int64?) -> FeatureAvailability {
        if microphoneDenied {
            return .setupRequired(reason: "Microphone access is off. Allow ListenToMe in Settings on Apple Watch → " +
                                  "Privacy & Security → Microphone.", action: "Open microphone settings on Apple Watch")
        }
        if let block = WatchCapturePolicy.startBlock(battery: battery, freeBytes: freeBytes) {
            return .temporarilyUnavailable(reason: WatchCapturePolicy.text(for: block))
        }
        return .ready
    }
}
