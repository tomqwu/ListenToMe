import Foundation
import ListenToMeCore

extension MeetingView {
    var currentCapabilityLocale: Locale {
        transcriptionLocaleID.isEmpty ? .current : Locale(identifier: transcriptionLocaleID)
    }

    func refreshFeatureAvailability() async {
        capabilityGeneration += 1
        let generation = capabilityGeneration
        let engine = ProviderSettings.transcriptionEngine
        let locale = currentCapabilityLocale
        recordingAvailability = .temporarilyUnavailable(reason: "Checking recording support…")
        let result = await MacDeviceCapabilities.recording(engine: engine, locale: locale)
        guard !Task.isCancelled, generation == capabilityGeneration,
              engine == ProviderSettings.transcriptionEngine, locale == currentCapabilityLocale else { return }
        recordingAvailability = result
        let appleReason = MacDeviceCapabilities.appleReason(locale: locale)
        session.aiEnabled = MacFeatureReadiness.aiCanRun(mode: ProviderSettings.aiMode, appleReason: appleReason)
        if ProviderSettings.aiMode == .apple { modelStatus = appleReason ?? "" }
    }
}
