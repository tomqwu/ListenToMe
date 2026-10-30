import Foundation
import Observation
import ListenToMeCore

/// Where "Ask your history" sends its question, decided by each app from its own AI settings.
struct HistoryAskRoute {
    /// Why asking is not possible right now (AI off, no model chosen…), or nil when it is.
    var unavailable: String?
    /// The off-device destination named in the disclosure, or nil when the answer stays on device.
    var destination: String?
    var responseLanguage: String?
    var makeProvider: @MainActor () throws -> any LLMProvider

    static func unavailable(_ reason: String) -> HistoryAskRoute {
        HistoryAskRoute(unavailable: reason, destination: nil, responseLanguage: nil,
                        makeProvider: { throw CocoaError(.featureUnsupported) })
    }

    var disclosure: String? { HistoryQuestion.disclosure(destination: destination) }
}

/// The History search field's state on both platforms (issue #57): keeps the on-device semantic
/// index in step with the archive, runs hybrid searches off the main thread, and answers a
/// question from the top retrieved passages with the user's chosen provider.
///
/// Searches and questions always read the History records *now* (`records`), never a list kept
/// from earlier, and every change to History bumps `generation`: results computed for an older
/// generation are never shown, so a deleted or cleared conversation cannot come back on screen.
@MainActor @Observable
final class HistorySearchModel {
    private(set) var answer = ""
    private(set) var answerQuestion = ""
    private(set) var citations: [HistoryCitation] = []
    private(set) var sentPassages = 0
    private(set) var isAsking = false
    private(set) var askError: String?
    /// Bumped whenever History may have lost a conversation (reload, delete, clear): results from
    /// an older generation are never shown. A save only re-runs the search, keeping the results on
    /// screen until the new ones arrive.
    private(set) var generation = 0
    private var results: [HistorySearchResult]?
    private var resultsQuery = ""
    private var resultsGeneration = -1

    /// The current History records, read when a search or a question runs.
    @ObservationIgnored var records: @MainActor () -> [SessionRecord] = { [] }
    @ObservationIgnored let index: HistoryIndex
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    @ObservationIgnored private var intendedEmbedder: (any HistoryEmbedder)?
    @ObservationIgnored private var semanticReady = true
    @ObservationIgnored private var removal: Task<Void, Never>?
    /// Bumped by Clear history / Delete all: index work queued before it is dropped.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdates: [String: SessionRecord] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var activeQuery = ""
    @ObservationIgnored private var askTask: Task<Void, Never>?
    @ObservationIgnored private var askToken = 0
    @ObservationIgnored private let syncDelay: Duration
    @ObservationIgnored private let searchDelay: Duration

    private static var shared: [String: HistorySearchModel] = [:]

    /// One model per archive, so Dev and Release builds (separate archives) never share an index.
    static func shared(besideArchive archive: URL) -> HistorySearchModel {
        let key = archive.standardizedFileURL.path
        if let existing = shared[key] { return existing }
        let model = HistorySearchModel(index: HistoryIndex(directory: HistoryIndex.directory(besideArchive: archive),
                                                         embedder: NaturalLanguageEmbedder()))
        shared[key] = model
        return model
    }

    /// Switch the same index actor so a late old backend cannot write into a replacement's files.
    func setEmbedder(_ embedder: any HistoryEmbedder) {
        intendedEmbedder = embedder
        semanticReady = false
        epoch += 1
        pendingSync?.cancel(); pendingUpdate?.cancel(); pendingUpdates = [:]
        maintenance?.cancel(); searchTask?.cancel()
        clearAnswer()
        generation += 1; results = nil; resultsQuery = ""
        let epoch = epoch
        maintenance = Task { [weak self] in
            guard let self, self.epoch == epoch, !Task.isCancelled else { return }
            _ = await self.prepareBackend(for: epoch)
            guard self.epoch == epoch, !Task.isCancelled else { return }
            self.historyChanged()
        }
    }

    /// A failed switch must not silently keep an optional backend active after opt-out.
    /// Preserve the intended choice for the next save/sync; only a complete rebuild opens Ask.
    private func prepareBackend(for expectedEpoch: Int) async -> Bool {
        guard epoch == expectedEpoch, !Task.isCancelled else { return false }
        if semanticReady { return true }
        guard let replacement = intendedEmbedder else { return false }
        do {
            try await index.setEmbedder(replacement)
            guard epoch == expectedEpoch, !Task.isCancelled else { return false }
            try await index.sync(records())
            guard epoch == expectedEpoch, !Task.isCancelled else { return false }
            semanticReady = true
            intendedEmbedder = nil
            historyChanged()
            return true
        } catch {
            // Current archive text is still searchable by words; never query the previous backend.
            return false
        }
    }

    init(index: HistoryIndex, syncDelay: Duration = .seconds(5), searchDelay: Duration = .milliseconds(250)) {
        self.index = index
        self.syncDelay = syncDelay
        self.searchDelay = searchDelay
    }

    // MARK: Index maintenance

    /// Reconciles the index with the whole archive after a quiet period (several reloads in a row
    /// cost one pass, and unchanged conversations are not embedded again).
    func sync(_ records: [SessionRecord]) {
        historyChanged()
        pendingSync?.cancel()
        let delay = syncDelay
        pendingSync = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            let epoch = self.epoch
            self.enqueue { [weak self] index in
                let report = try? await index.sync(records)
                guard let self, self.epoch == epoch, !Task.isCancelled,
                      (report?.embedded ?? 0) + (report?.removed ?? 0) > 0 else { return }
                self.historyChanged()
            }
        }
    }

    /// Embeds a saved conversation once saving has paused: a recording saves every few seconds, and
    /// only its latest text needs vectors, so each save restarts the wait.
    func update(_ record: SessionRecord) {
        if !activeQuery.isEmpty { search(activeQuery) }
        pendingUpdates[record.id] = record
        pendingUpdate?.cancel()
        let delay = syncDelay
        pendingUpdate = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            let records = Array(self.pendingUpdates.values)
            self.pendingUpdates = [:]
            let epoch = self.epoch
            self.enqueue { [weak self] index in
                var published = false
                for record in records {
                    guard let self, self.epoch == epoch, !Task.isCancelled else { return }
                    if (try? await index.update(record)) == true { published = true }
                }
                guard published, let self, self.epoch == epoch, !Task.isCancelled else { return }
                self.historyChanged()
            }
        }
    }

    /// A conversation was deleted. Its vectors go now — not behind a sync that is still running,
    /// which stops at its next conversation and never embeds this one again.
    func forget(id: String) {
        pendingUpdates[id] = nil
        // An in-flight answer captured records before deletion; it must not restore deleted text
        // or citations after the row disappears. Clear completed answers for the same reason.
        clearAnswer()
        historyChanged()
        removeNow { index in try? await index.remove(id: id) }
    }

    /// History was cleared: every vector goes, the running sync is cancelled and anything queued
    /// before the clear is dropped.
    func forgetAll() {
        epoch += 1
        pendingSync?.cancel()
        pendingUpdate?.cancel()
        pendingUpdates = [:]
        maintenance?.cancel()
        clearAnswer()
        historyChanged()
        removeNow { index in try? await index.removeAll() }
    }

    /// Runs `work` in order behind earlier maintenance, unless History was cleared since.
    private func enqueue(_ work: @escaping @MainActor @Sendable (HistoryIndex) async -> Void) {
        let previous = maintenance
        let index = index
        let epoch = epoch
        maintenance = Task { [weak self] in
            await previous?.value
            guard let self, self.epoch == epoch, !Task.isCancelled else { return }
            guard await self.prepareBackend(for: epoch) else {
                guard self.epoch == epoch, !Task.isCancelled else { return }
                self.historyChanged()
                return
            }
            await work(index)
        }
    }

    /// Removals do not wait for maintenance: the index actor runs them at the running sync's next
    /// step, and they run in the order they were asked for.
    private func removeNow(_ work: @escaping @Sendable (HistoryIndex) async -> Void) {
        let previous = removal
        let index = index
        removal = Task {
            await previous?.value
            await work(index)
        }
    }

    // MARK: Search

    /// Hybrid results for `query`, or nil while they are being computed or no longer match History
    /// (the view then shows the plain keyword matches).
    func results(for query: String) -> [HistorySearchResult]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == resultsQuery, resultsGeneration == generation else { return nil }
        return results
    }

    /// Searches the current History for `query`, debounced.
    func search(_ query: String) {
        searchTask?.cancel()
        activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeQuery.isEmpty else { results = nil; resultsQuery = ""; return }
        let trimmed = activeQuery
        let delay = searchDelay
        let index = index
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            let generation = self.generation
            let current = self.records()
            let found: [HistorySearchResult]
            if self.semanticReady {
                found = await index.search(trimmed, in: current)
            } else {
                found = SessionSearch.search(current, query: trimmed).map {
                    HistorySearchResult(record: $0, matchesWords: true, isRelated: false, snippet: nil)
                }
            }
            guard !Task.isCancelled, generation == self.generation, trimmed == self.activeQuery else { return }
            self.results = found
            self.resultsQuery = trimmed
            self.resultsGeneration = generation
        }
    }

    /// History changed: results computed before are void, and the search on screen runs again.
    private func historyChanged() {
        generation += 1
        if !activeQuery.isEmpty { search(activeQuery) }
    }

    // MARK: Ask your history

    /// Retrieves the best passages for `question` from the current History and streams an answer
    /// from `route`'s provider. Only those passages are sent; the citations point at their
    /// conversations. Stop or a new question ends it; Clear history clears it.
    func ask(_ question: String, route: HistoryAskRoute,
             describe: @escaping (Error) -> String = { $0.localizedDescription }) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        guard semanticReady else {
            askError = "The History search model is not ready. Exact-word search is available; "
                + "save or reload History to retry before asking."
            answerQuestion = trimmed
            return
        }
        if let reason = route.unavailable { askError = reason; answerQuestion = trimmed; return }
        askTask?.cancel()
        askToken += 1
        let token = askToken
        answer = ""; citations = []; askError = nil; sentPassages = 0
        answerQuestion = trimmed
        isAsking = true
        let index = index
        let records = records()
        askTask = Task { [weak self] in
            defer { if self?.askToken == token { self?.isAsking = false } }
            @MainActor func current() -> Bool { !Task.isCancelled && self?.askToken == token }
            do {
                let provider = try route.makeProvider()
                let passages = await index.retrieve(trimmed, in: records)
                guard current() else { return }
                let budget = min(provider.maxPromptCharacters ?? HistoryQuestion.characterBudget,
                                 HistoryQuestion.characterBudget)
                guard let built = HistoryQuestion.request(question: trimmed, passages: passages,
                                                          responseLanguage: route.responseLanguage,
                                                          characterBudget: budget) else {
                    self?.askError = "No saved conversation is close enough to that question to answer it."
                    return
                }
                self?.sentPassages = built.sent.count
                var text = ""
                for try await delta in provider.stream(built.request) {
                    guard current() else { return }
                    text += delta
                    guard text.count <= 20_000 else { break }
                    self?.answer = text
                }
                guard current() else { return }
                self?.answer = text
                self?.citations = HistoryQuestion.citations(in: text, sent: built.sent)
            } catch {
                guard current(), !(error is CancellationError) else { return }
                self?.askError = describe(error)
            }
        }
    }

    func cancelAsk() {
        askToken += 1
        askTask?.cancel()
        askTask = nil
        isAsking = false
    }

    /// Waits for the index work queued so far, removals included (tests, and callers that need the
    /// index settled).
    func waitForMaintenance() async {
        await maintenance?.value
        await removal?.value
    }

    /// Waits for the pending debounced sync to start, then for the index work it queued.
    func waitForSync() async {
        await pendingSync?.value
        await waitForMaintenance()
    }

    /// Waits for the pending debounced saves and their queued index work.
    func waitForUpdates() async {
        await pendingUpdate?.value
        await waitForMaintenance()
    }

    /// Captures queued saves before testing cancellation of a later maintenance wrapper.
    func waitForUpdateEnqueue() async -> Task<Void, Never>? {
        await pendingUpdate?.value
        return maintenance
    }

    /// Waits for the search being computed, if any.
    func waitForSearch() async { await searchTask?.value }

    /// Waits for the answer being streamed, if any.
    func waitForAnswer() async { await askTask?.value }

    /// Clears the answer when the question it answered is no longer in the field.
    func clearAnswer() {
        cancelAsk()
        answer = ""; answerQuestion = ""; citations = []; askError = nil; sentPassages = 0
    }
}
