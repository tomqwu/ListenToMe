import Foundation
import ListenToMeCore

extension MeetingView {
    var currentCapabilityLocale: Locale {
        transcriptionLocaleID.isEmpty ? .current : Locale(identifier: transcriptionLocaleID)
    }

    func refreshFeatureAvailability() async { await requestFeatureRefresh().value }

    @discardableResult
    func requestFeatureRefresh() -> Task<Void, Never> {
        let engine = ProviderSettings.transcriptionEngine
        let locale = currentCapabilityLocale
        recordingAvailability = .temporarilyUnavailable(reason: "Checking recording support…")
        return capabilityWork.start(load: {
            await MacDeviceCapabilities.recording(engine: engine, locale: locale)
        }, apply: { result in
            guard engine == ProviderSettings.transcriptionEngine, locale == currentCapabilityLocale else { return }
            recordingAvailability = result
            let appleReason = MacDeviceCapabilities.appleReason(locale: locale)
            session.aiEnabled = MacFeatureReadiness.aiCanRun(mode: ProviderSettings.aiMode, appleReason: appleReason)
            if ProviderSettings.aiMode == .apple { modelStatus = appleReason ?? "" }
        })
    }
}
