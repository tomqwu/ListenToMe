import Foundation
import ListenToMeCore
import Observation
import Speech

/// Languages supported by the active on-device modules: advanced speech on Mac, and advanced speech
/// plus dictation fallback on iOS. Read at launch and when the language picker refreshes.
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

    struct Environment {
        var speechAvailable: () -> Bool = { SpeechTranscriber.isAvailable }
        var speechLocales: () async -> [Locale] = { await SpeechTranscriber.supportedLocales }
        var dictationLocales: () async -> [Locale] = { await DictationTranscriber.supportedLocales }
        var speechLocale: (Locale) async -> Locale? = { await SpeechTranscriber.supportedLocale(equivalentTo: $0) }
        var dictationLocale: (Locale) async -> Locale? = { await DictationTranscriber.supportedLocale(equivalentTo: $0) }
        var installed: (any SpeechModule) async -> Bool = { await AssetInventory.status(forModules: [$0]) == .installed }
        #if os(iOS)
        var includeDictation = true
        #else
        var includeDictation = false
        #endif
    }
    @ObservationIgnored private let environment: Environment
    init(environment: Environment = Environment()) { self.environment = environment }

    /// Reads the OS lists, joining a read already in progress.
    func load() async {
        if let loading { return await loading.value }
        let task = Task { @MainActor in
            let lists = await Self.read(environment: environment)
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

    private static func read(environment: Environment) async -> (supported: [String], installed: [String]) {
        let hasAdvanced = environment.speechAvailable()
        let advanced = hasAdvanced ? await environment.speechLocales() : []
        let fallback = environment.includeDictation ? await environment.dictationLocales() : []
        let identifiers = Set((advanced + fallback).map { $0.identifier(.bcp47) }).sorted()
        var supported: [String] = []
        var installed: [String] = []
        for identifier in identifiers {
            let locale = Locale(identifier: identifier)
            let module: any SpeechModule
            if hasAdvanced, let equivalent = await environment.speechLocale(locale) {
                module = SpeechTranscriber(locale: equivalent, transcriptionOptions: [], reportingOptions: [],
                                           attributeOptions: [.audioTimeRange])
            } else if environment.includeDictation, let equivalent = await environment.dictationLocale(locale) {
                module = DictationTranscriber(locale: equivalent, contentHints: [], transcriptionOptions: [],
                                              reportingOptions: [], attributeOptions: [.audioTimeRange])
            } else { continue }
            supported.append(identifier)
            if await environment.installed(module) { installed.append(identifier) }
        }
        return (supported, installed)
    }
}
