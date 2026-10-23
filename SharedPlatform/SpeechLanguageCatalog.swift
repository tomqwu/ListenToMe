import Foundation
import ListenToMeCore
import Observation
import Speech

/// The languages this OS can transcribe on the device, read from `SpeechTranscriber.supportedLocales`
/// once at launch and kept for the transcription-language pickers on macOS and iOS (issue #172).
/// `AssetInventory` says which ones already have their speech model installed; the pickers refresh
/// that when they appear, since recording downloads a model on first use. The ordering and grouping
/// rules are `TranscriptionLanguageCatalog` in Core.
@MainActor @Observable
final class SpeechLanguageCatalog {
    static let shared = SpeechLanguageCatalog()

    /// BCP 47 identifiers, as the OS lists them. Empty until loaded, or where on-device transcription
    /// is unavailable (the simulator), in which case the pickers offer the curated common languages.
    private(set) var supported: [String] = []
    private(set) var installed: [String] = []
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// Reads the OS lists, joining a read already in progress.
    func load() async {
        if let loading { return await loading.value }
        let task = Task { @MainActor in
            let lists = await Self.read()
            supported = lists.supported
            installed = lists.installed
        }
        loading = task
        await task.value
        loading = nil
    }

    /// The picker's options; see `TranscriptionLanguageCatalog.groups`.
    func groups(excluding: [String] = [], selected: String?, label: (String) -> String) -> TranscriptionLanguageGroups {
        TranscriptionLanguageCatalog.groups(supported: supported, installed: installed, excluding: excluding,
                                            selected: selected, label: label)
    }

    private nonisolated static func read() async -> (supported: [String], installed: [String]) {
        guard SpeechTranscriber.isAvailable else { return ([], []) }
        let locales = await SpeechTranscriber.supportedLocales
        var installed: [String] = []
        for locale in locales {
            // The same module the recorders build, so "installed" means recording needs no download.
            let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                           attributeOptions: [.audioTimeRange])
            if await AssetInventory.status(forModules: [module]) == .installed {
                installed.append(locale.identifier(.bcp47))
            }
        }
        return (locales.map { $0.identifier(.bcp47) }, installed)
    }
}
