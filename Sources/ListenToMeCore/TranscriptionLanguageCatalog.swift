import Foundation

/// The transcription languages a picker offers, split into those whose on-device speech model is
/// already installed and those that download on first use (issue #172).
public struct TranscriptionLanguageGroups: Equatable, Sendable {
    public var installed: [String]
    public var downloadable: [String]

    public init(installed: [String] = [], downloadable: [String] = []) {
        self.installed = installed
        self.downloadable = downloadable
    }

    /// Every option, installed first.
    public var all: [String] { installed + downloadable }
}

/// Pure rules for the transcription-language pickers on macOS and iOS (issue #172).
///
/// The options come from `SpeechTranscriber.supportedLocales`, so any language this OS can transcribe
/// on the device is selectable, not only a curated few. The curated list only orders the common
/// languages first. The same supported list is what `LanguageDetectionPolicy` switches among, so a
/// language Automatic can switch to is always one the user could also pick.
public enum TranscriptionLanguageCatalog {
    /// The languages most users pick, in the order they lead each group. An ordering hint only: one
    /// the OS does not support is not offered. It is also the list offered when the OS list is not
    /// available (an older OS, or a simulator without speech assets).
    public static let common = ["en-US", "en-GB", "zh-CN", "zh-TW", "yue-CN", "ja-JP", "ko-KR",
                                "es-ES", "fr-FR", "de-DE"]

    /// `supported` grouped by `installed`, each group with the `common` languages first in that order
    /// and the rest sorted by `label` (then identifier, so the order is stable).
    ///
    /// Identifiers are compared written either way ("en_US" or "en-US", any case) and come back in
    /// BCP 47 form, once each. `excluding` drops languages the picker already offers elsewhere, such as
    /// the device's own. `selected`, the stored choice, is kept as a downloadable option when the OS no
    /// longer lists it, so the picker never shows a blank selection. An empty `supported` falls back to
    /// `common`.
    public static func groups(supported: [String], installed: [String], excluding: [String] = [],
                              selected: String? = nil, label: (String) -> String) -> TranscriptionLanguageGroups {
        let excluded = Set(excluding.map(key))
        let installedKeys = Set(installed.map(key))
        var seen = Set<String>()
        var options: [String] = []
        for identifier in (supported.isEmpty ? common : supported) + [selected].compactMap({ $0 }) {
            let canonical = bcp47(identifier)
            let id = key(canonical)
            guard !canonical.isEmpty, !excluded.contains(id), seen.insert(id).inserted else { continue }
            options.append(canonical)
        }
        let sorted = ordered(options, label: label)
        return TranscriptionLanguageGroups(installed: sorted.filter { installedKeys.contains(key($0)) },
                                           downloadable: sorted.filter { !installedKeys.contains(key($0)) })
    }

    /// `identifiers` with the `common` ones first, in `common`'s order, then the rest by label.
    public static func ordered(_ identifiers: [String], label: (String) -> String) -> [String] {
        let rank = Dictionary(common.enumerated().map { (key($0.element), $0.offset) }, uniquingKeysWith: min)
        let labelled = identifiers.map { (id: $0, label: label($0), rank: rank[key($0)]) }
        return labelled.sorted { lhs, rhs in
            switch (lhs.rank, rhs.rank) {
            case let (left?, right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                let order = lhs.label.localizedStandardCompare(rhs.label)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        }.map(\.id)
    }

    /// The BCP 47 spelling of a locale identifier: "en_US" becomes "en-US". Surrounding whitespace is
    /// dropped; letter case is kept as given.
    public static func bcp47(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
    }

    /// Whether two identifiers name the same locale, however they are written.
    public static func same(_ lhs: String, _ rhs: String) -> Bool { key(lhs) == key(rhs) }

    private static func key(_ identifier: String) -> String { bcp47(identifier).lowercased() }
}
