import Foundation
import ListenToMeCore
import Observation

/// Domain vocabularies and My terms for one app window (issue #222), shared by iOS and macOS. Settings
/// are stored on this device with the app's other settings (so a device backup includes them, like any
/// setting); the suggestion classifier runs on this device and nothing here is sent anywhere.
@MainActor @Observable
final class SessionVocabulary {
    /// The suggestion banner's state for the conversation it was made for.
    struct Suggestion: Equatable {
        enum Stage: Equatable { case offered, added }
        let domain: VocabularyDomain
        let conversationID: String
        var stage = Stage.offered
    }

    let catalog: VocabularyCatalog
    @ObservationIgnored private let store: VocabularySettingsStore
    @ObservationIgnored private let classifier: VocabularyClassifier
    var settings: VocabularySettings {
        didSet { if settings != oldValue { store.save(settings) } }
    }
    private(set) var tracker = VocabularySuggestionTracker(conversationID: "")
    private(set) var suggestion: Suggestion?
    /// The classification in flight, if any; tests await it.
    @ObservationIgnored private(set) var check: Task<Void, Never>?
    /// The transcript line "Add to My terms" was chosen from, while its sheet is open (macOS).
    var termSourceLine: String?
    /// Final lines of the open conversation already seen by `heard(transcript:conversationID:live:)`.
    @ObservationIgnored private var countedLines = 0
    /// The correction lookup for the last active vocabulary, rebuilt only when that vocabulary changes.
    @ObservationIgnored private var correctionIndex: VocabularyPrompt.CorrectionIndex?
    @ObservationIgnored private var correctionIndexSource: ActiveVocabulary?

    init(defaults: UserDefaults = .standard, catalog: VocabularyCatalog = .bundled,
         classifier: VocabularyClassifier? = nil) {
        self.catalog = catalog
        store = VocabularySettingsStore(defaults: defaults)
        settings = store.load()
        self.classifier = classifier ?? VocabularyClassifier(catalog: catalog)
    }

    /// Re-reads the stored settings after another view (macOS Settings) changed them.
    func reloadSettings() { settings = store.load() }

    func active(for conversationID: String) -> ActiveVocabulary {
        ActiveVocabulary(settings: settings, conversationDomainIDs: domainIDs(for: conversationID), catalog: catalog)
    }

    /// `heard` is the conversation's recent speech: My terms already said there are kept first.
    func recognitionTerms(for conversationID: String, heard: String? = nil) -> [String] {
        active(for: conversationID).recognitionTerms(heard: heard)
    }

    /// The prepared correction lookup for this conversation's vocabulary (a `Sendable` value, so the
    /// glossary for each phrase can be built off the main actor).
    func correctionLookup(for conversationID: String) -> VocabularyPrompt.CorrectionIndex {
        let active = active(for: conversationID)
        if let correctionIndex, correctionIndexSource == active { return correctionIndex }
        let index = VocabularyPrompt.CorrectionIndex(active)
        correctionIndex = index
        correctionIndexSource = active
        return index
    }

    /// Presets on for this conversation only (added from the banner).
    func domainIDs(for conversationID: String) -> Set<String> {
        tracker.conversationID == conversationID ? tracker.addedIDs : []
    }

    func isActive(_ id: String, in conversationID: String) -> Bool {
        settings.isDefault(id) || domainIDs(for: conversationID).contains(id)
    }

    /// The banner to show for `conversationID`, if any.
    func banner(for conversationID: String) -> Suggestion? {
        suggestion?.conversationID == conversationID ? suggestion : nil
    }

    // MARK: - Suggestions

    /// Counts a finalized line and, once enough speech has been heard, classifies the recent speech off
    /// the main actor. `recent` is only read when a check is due.
    func heard(_ line: String, conversationID: String, recent: @autoclosure () -> String) {
        tracker.begin(conversationID: conversationID)
        if let shown = suggestion, shown.conversationID != conversationID { suggestion = nil }
        tracker.heard(line)
        guard check == nil, let excluded = tracker.dueCheck(settings: settings) else { return }
        let classifier = classifier
        let text = recent()
        check = Task {
            // The first check loads Apple's sentence embedding; it must never stall the transcript.
            let found = await Task.detached(priority: .utility) {
                classifier.suggestion(for: text, excluding: excluded)
            }.value
            check = nil
            offer(found, conversationID: conversationID)
        }
    }

    /// The whole finalized transcript, for a platform that observes it rather than each line (macOS).
    /// Only lines that arrive while `live` (recording) count toward a suggestion: a restored or imported
    /// conversation, or a store that was replaced, only moves the baseline and is never classified.
    func heard(transcript lines: [String], conversationID: String, live: Bool) {
        if tracker.conversationID != conversationID {
            tracker.begin(conversationID: conversationID)
            if let shown = suggestion, shown.conversationID != conversationID { suggestion = nil }
            countedLines = lines.count
        }
        guard live, lines.count > countedLines else { countedLines = lines.count; return }
        for line in lines[countedLines...] {
            heard(line, conversationID: conversationID, recent: lines.suffix(200).joined(separator: " "))
        }
        countedLines = lines.count
    }

    /// Shows the banner for `id` unless the conversation changed or the preset became active meanwhile.
    func offer(_ id: String?, conversationID: String) {
        guard let id, tracker.conversationID == conversationID, !isActive(id, in: conversationID),
              !tracker.addedIDs.contains(id), suggestion == nil || suggestion?.stage == .added,
              let domain = catalog.domain(id: id) else { return }
        tracker.markOffered(id)
        suggestion = Suggestion(domain: domain, conversationID: conversationID)
    }

    /// "Add": on for this conversation; the banner then offers "Use by default".
    func addSuggested() {
        guard var current = suggestion, current.stage == .offered else { return }
        add(current.domain.id, to: current.conversationID)
        current.stage = .added
        suggestion = current
    }

    func add(_ id: String, to conversationID: String) {
        tracker.begin(conversationID: conversationID)
        tracker.add(id)
    }

    func remove(_ id: String, from conversationID: String) {
        guard tracker.conversationID == conversationID else { return }
        tracker.remove(id)
    }

    /// "Use by default": on for every conversation from now on.
    func useSuggestedByDefault() {
        guard let current = suggestion else { return }
        settings.setDefault(current.domain.id, true)
        suggestion = nil
    }

    /// "Not now": hidden; this preset is not offered again in this conversation.
    func dismissSuggestion() { suggestion = nil }

    /// "Don't suggest … again".
    func muteSuggested() {
        guard let current = suggestion else { return }
        settings.setMuted(current.domain.id, true)
        suggestion = nil
    }

    // MARK: - My terms

    /// Adds a term to My terms, returning why it could not be added (nil on success).
    @discardableResult
    func addTerm(_ term: String) -> String? {
        if let reason = settings.rejection(of: term) { return reason }
        settings.addTerm(term)
        return nil
    }
}
