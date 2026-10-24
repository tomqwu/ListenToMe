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
@MainActor @Observable
final class HistorySearchModel {
    private(set) var results: [HistorySearchResult]?
    private(set) var resultsQuery = ""
    private(set) var answer = ""
    private(set) var answerQuestion = ""
    private(set) var citations: [HistoryCitation] = []
    private(set) var sentPassages = 0
    private(set) var isAsking = false
    private(set) var askError: String?

    @ObservationIgnored let index: HistoryIndex
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdates: [String: SessionRecord] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var askTask: Task<Void, Never>?
    @ObservationIgnored private let syncDelay: Duration
    @ObservationIgnored private let searchDelay: Duration
    /// The search on screen, re-run once a sync has embedded new conversations.
    @ObservationIgnored private var lastSearch: (query: String, records: [SessionRecord])?

    private static var shared: [String: HistorySearchModel] = [:]

    /// One model per archive, so Dev and Release builds (separate archives) never share an index.
    static func shared(besideArchive archive: URL) -> HistorySearchModel {
        let key = archive.standardizedFileURL.path
        if let existing = shared[key] { return existing }
        let model = HistorySearchModel(index: HistoryIndex(directory: HistoryIndex.directory(besideArchive: archive)))
        shared[key] = model
        return model
    }

    init(index: HistoryIndex, syncDelay: Duration = .seconds(5), searchDelay: Duration = .milliseconds(250)) {
        self.index = index
        self.syncDelay = syncDelay
        self.searchDelay = searchDelay
    }

    // MARK: Index maintenance — every call runs on the index actor, in the order it was made.

    /// Reconciles the index with the whole archive after a quiet period (several reloads in a row
    /// cost one pass, and unchanged conversations are not embedded again).
    func sync(_ records: [SessionRecord]) {
        pendingSync?.cancel()
        let delay = syncDelay
        pendingSync = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.enqueue { [weak self] index in
                let report = try? await index.sync(records)
                guard (report?.embedded ?? 0) + (report?.removed ?? 0) > 0 else { return }
                await self?.refreshSearch()
            }
        }
    }

    /// Embeds a saved conversation once saving has paused: a recording saves every few seconds, and
    /// only its latest text needs vectors, so each save restarts the wait.
    func update(_ record: SessionRecord) {
        pendingUpdates[record.id] = record
        pendingUpdate?.cancel()
        let delay = syncDelay
        pendingUpdate = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            let records = Array(self.pendingUpdates.values)
            self.pendingUpdates = [:]
            self.enqueue { index in for record in records { _ = try? await index.update(record) } }
        }
    }

    /// A conversation was deleted: its vectors go with it.
    func forget(id: String) {
        pendingUpdates[id] = nil
        results?.removeAll { $0.id == id }
        citations.removeAll { $0.recordID == id }
        enqueue { index in try? await index.remove(id: id) }
    }

    /// History was cleared: every vector goes.
    func forgetAll() {
        pendingSync?.cancel()
        pendingUpdate?.cancel()
        pendingUpdates = [:]
        results = nil
        clearAnswer()
        enqueue { index in try? await index.removeAll() }
    }

    private func enqueue(_ work: @escaping @Sendable (HistoryIndex) async -> Void) {
        let previous = maintenance
        let index = index
        maintenance = Task {
            await previous?.value
            await work(index)
        }
    }

    // MARK: Search

    /// Hybrid results for `query`, debounced. Until they arrive, `results` is nil and the view shows
    /// the plain keyword matches it already has.
    func search(_ query: String, in records: [SessionRecord]) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = nil; resultsQuery = ""; lastSearch = nil; return }
        lastSearch = (trimmed, records)
        if trimmed != resultsQuery { results = nil }
        let delay = searchDelay
        let index = index
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            let found = await index.search(trimmed, in: records)
            guard !Task.isCancelled, let self else { return }
            self.results = found
            self.resultsQuery = trimmed
        }
    }

    private func refreshSearch() {
        guard let lastSearch else { return }
        search(lastSearch.query, in: lastSearch.records)
    }

    // MARK: Ask your history

    /// Retrieves the best passages for `question` and streams an answer from `route`'s provider.
    /// Only those passages are sent; the answer's citations point back at their conversations.
    func ask(_ question: String, in records: [SessionRecord], route: HistoryAskRoute,
             describe: @escaping (Error) -> String = { $0.localizedDescription }) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        if let reason = route.unavailable { askError = reason; return }
        askTask?.cancel()
        answer = ""; citations = []; askError = nil; sentPassages = 0
        answerQuestion = trimmed
        isAsking = true
        let index = index
        askTask = Task { [weak self] in
            defer { self?.isAsking = false }
            do {
                let provider = try route.makeProvider()
                let passages = await index.retrieve(trimmed, in: records)
                let budget = min(provider.maxPromptCharacters ?? 24_000, 24_000)
                guard let built = HistoryQuestion.request(question: trimmed, passages: passages,
                                                          responseLanguage: route.responseLanguage,
                                                          characterBudget: budget) else {
                    self?.askError = "Nothing in your saved conversations matches that question."
                    return
                }
                self?.sentPassages = built.sent.count
                var text = ""
                for try await delta in provider.stream(built.request) {
                    try Task.checkCancellation()
                    text += delta
                    guard text.count <= 20_000 else { break }
                    self?.answer = text
                }
                self?.answer = text
                self?.citations = HistoryQuestion.citations(in: text, sent: built.sent)
            } catch is CancellationError {
                return
            } catch {
                self?.askError = describe(error)
            }
        }
    }

    func cancelAsk() {
        askTask?.cancel()
        askTask = nil
        isAsking = false
    }

    /// Waits for the index work queued so far (tests, and callers that need the index settled).
    func waitForMaintenance() async { await maintenance?.value }

    /// Waits for the answer being streamed, if any.
    func waitForAnswer() async { await askTask?.value }

    /// Clears the answer when the question it answered is no longer in the field.
    func clearAnswer() {
        cancelAsk()
        answer = ""; answerQuestion = ""; citations = []; askError = nil; sentPassages = 0
    }
}
