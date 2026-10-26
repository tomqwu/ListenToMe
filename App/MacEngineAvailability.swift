import Foundation
import Observation
import ListenToMeCore

/// The native menu and its actions share this state; no old check may restore a stale choice.
@MainActor @Observable
final class MacEngineAvailability {
    static let engines = ["speechAnalyzer", "speechRecognizer", "whisperKit"]
    private(set) var availability: [String: FeatureAvailability] = [:]
    private var generation = 0
    private var checkedLocale: Locale?
    @ObservationIgnored private let query: (String, Locale) async -> FeatureAvailability

    init(query: @escaping (String, Locale) async -> FeatureAvailability = { engine, locale in
        await MacDeviceCapabilities.recording(engine: engine, locale: locale, checkMicrophone: false)
    }) {
        self.query = query
    }

    var choices: [String] { Self.engines.filter { availability[$0]?.canConfigure == true } }

    func choices(for locale: Locale) -> [String] { checkedLocale == locale ? choices : [] }

    func status(for engine: String, locale: Locale? = nil) -> FeatureAvailability {
        if let locale, checkedLocale != locale { return .temporarilyUnavailable(reason: "Checking recording support…") }
        return availability[engine] ?? .temporarilyUnavailable(reason: "Checking recording support…")
    }

    func select(_ engine: String, current: String, locale: Locale? = nil) -> String {
        if let locale, checkedLocale != locale { return current }
        return choices.contains(engine) ? engine : current
    }

    func refresh(locale: Locale) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let request = generation
        checkedLocale = nil
        availability = [:]
        var result: [String: FeatureAvailability] = [:]
        for engine in Self.engines {
            guard !Task.isCancelled, request == generation else { return }
            result[engine] = await query(engine, locale)
        }
        guard !Task.isCancelled, request == generation else { return }
        checkedLocale = locale
        availability = result
    }
}
