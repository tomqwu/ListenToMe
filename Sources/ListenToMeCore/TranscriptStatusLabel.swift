import Foundation

/// The transcript pane's status chip: "idle", "preparing", or "live · N src".
///
/// `N` is the number of distinct speaker sources actually captured so far, so the chip never claims
/// system audio that isn't being captured. "preparing" matters because a session is `isRunning`
/// from the moment Start is pressed, but no audio flows until the on-device speech model is warm —
/// saying "live" through a multi-minute first-run download overstates what the app is doing
/// (issues #136, #147).
public enum TranscriptStatusLabel {
    public static func text(isRunning: Bool, isPreparing: Bool, sources: Int) -> String {
        guard isRunning else { return "idle" }
        guard !isPreparing else { return "preparing" }
        return sources > 0 ? "live · \(sources) src" : "live"
    }
}
