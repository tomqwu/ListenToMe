import Foundation
import ListenToMeCore

extension MobileSession {
    /// Metadata only: no microphone prompt, audio activation or model download.
    func refreshRecordingSupport(publish: Bool = true) async {
        recordingSupportGeneration += 1
        let generation = recordingSupportGeneration
        let locale = recordingLanguage
        recordingAvailability = .temporarilyUnavailable(reason: "Checking recording support…")
        let result = await recordingSupport(Locale(identifier: locale))
        guard !Task.isCancelled, generation == recordingSupportGeneration, locale == recordingLanguage else { return }
        recordingAvailability = result
        if publish { publishWatchStatus() }
    }

    func invalidateRecordingSupport() {
        recordingSupportGeneration += 1
        recordingAvailability = .temporarilyUnavailable(reason: "Checking recording support…")
    }
}
