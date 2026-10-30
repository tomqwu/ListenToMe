import Foundation

/// A passage retrieved for "Ask your history": the only conversation text an answer is given.
public struct HistoryPassage: Sendable, Equatable, Identifiable {
    public var id: String { "\(recordID)#\(ordinal)" }
    public let recordID: String
    public let title: String
    public let date: Date
    public let source: HistorySource
    public let ordinal: Int
    public let text: String
    /// Ordering score, fused from ranks when multiple independent model populations are present.
    /// This is not a confidence probability and is not comparable across different searches.
    public let score: Float
    public init(recordID: String, title: String, date: Date, source: HistorySource, ordinal: Int,
                text: String, score: Float) {
        self.recordID = recordID; self.title = title; self.date = date; self.source = source
        self.ordinal = ordinal; self.text = text; self.score = score
    }
}

/// What one `sync` did, for tests and diagnostics.
public struct HistoryIndexReport: Sendable, Equatable {
    public var embedded = 0
    public var removed = 0
    public var unchanged = 0
    public init(embedded: Int = 0, removed: Int = 0, unchanged: Int = 0) {
        self.embedded = embedded; self.removed = removed; self.unchanged = unchanged
    }
}

/// The on-device semantic index of saved conversations (issue #57).
///
/// - Stores only vectors, chunk ordinals and a fingerprint per conversation — never the text, which
///   stays in the archive and is re-derived (`HistoryChunker` is deterministic) for snippets.
/// - Lives beside the archive in `Search Index/`, one small file per conversation, so a Dev and a
///   Release build that keep separate archives also keep separate indexes. The folder is always
///   excluded from backup: it is derived data, rebuilt from the archive whenever it is missing,
///   damaged, or written by another index version or embedding method.
/// - `sync` is incremental: only changed passages in changed conversations are embedded again, and a
///   conversation no longer in the archive loses its vectors. An actor, so all of it runs off the
///   main thread; vectors are held in memory only up to `memoryBudget` and read from disk beyond it.
public actor HistoryIndex {
    public static let version = 2
    public static let folderName = "Search Index"
    static let fileExtension = "vectors"

    public nonisolated let directory: URL
    private var embedder: any HistoryEmbedder
    private let memoryBudget: Int
    private let parameters: HistoryRanking.Parameters
    private let fileManager = FileManager.default
    /// Fingerprint and model tags of every stored conversation; nil until the folder was read.
    private var catalog: [String: (fingerprint: UInt64, models: Set<String>)]?
    private var cache: [String: StoredRecordVectors] = [:]
    private var cachedBytes = 0
    /// Bumped by every removal, so a sync that is still running with an older list of conversations
    /// stops at the next conversation instead of embedding ones that were deleted meanwhile.
    private var removals = 0
    /// Publication revisions fence suspended searches; tokens make the latest save own its record.
    private var revision = 0
    private var pending: [String: UUID] = [:]
    private var requestSerial = 0
    private var requests: [String: Int] = [:]
    /// Conversations deleted while this index is open. Their IDs are never embedded again, whatever
    /// list of conversations a later call still carries.
    private var deleted: Set<String> = []

    public init(directory: URL, embedder: any HistoryEmbedder = NaturalLanguageEmbedder(),
                memoryBudget: Int = 32 << 20, parameters: HistoryRanking.Parameters = .init()) {
        self.directory = directory
        self.embedder = embedder
        self.memoryBudget = memoryBudget
        self.parameters = parameters
    }

    /// The index folder for an archive folder: its sibling, inside the same app data folder.
    public static func directory(besideArchive archive: URL) -> URL {
        archive.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    /// Replaces only the derived backend on this actor, so old suspended work cannot republish.
    /// A storage failure leaves the old backend selected; its derived data may need rebuilding.
    public func setEmbedder(_ replacement: any HistoryEmbedder, forceRefresh: Bool = false) throws {
        try Task.checkCancellation()
        guard forceRefresh || replacement.signature != embedder.signature else { return }
        try wipe()
        let previous = embedder
        embedder = replacement
        catalog = nil
        do { try prepare() } catch {
            embedder = previous
            catalog = nil
            throw error
        }
    }

    /// IDs that currently have vectors on disk.
    public func indexedIDs() throws -> Set<String> { Set(try load().keys) }

    // MARK: - Maintenance

    /// Brings the index in line with `records`: embeds new or changed conversations and drops the
    /// vectors of conversations that are gone. Cancellation never publishes a partial conversation.
    @discardableResult
    public func sync(_ records: [SessionRecord]) async throws -> HistoryIndexReport {
        guard !Task.isCancelled else { return HistoryIndexReport() }
        let mine = removals
        var report = HistoryIndexReport()
        let wanted = Set(records.map(\.id))
        requestSerial += 1
        let request = requestSerial
        // Reserve the whole archive snapshot before the first await, including unvisited records.
        // A newer snapshot also revokes records absent from its archive.
        for id in Set(requests.keys).union(wanted) { requests[id] = request }
        for id in pending.keys where !wanted.contains(id) { pending[id] = nil }
        for id in try load().keys where !wanted.contains(id) {
            try deleteFile(id)
            report.removed += 1
        }
        for record in records {
            guard !Task.isCancelled, removals == mine else { break }
            switch try await embed(record, request: request) {
            case .unchanged: report.unchanged += 1
            case .embedded: report.embedded += 1; await Task.yield()
            case .skipped: continue
            }
        }
        return report
    }

    /// Embeds one saved conversation if its text changed. Leaves every other conversation alone,
    /// so it is the cheap call to make after each save. Returns true when new vectors were written.
    @discardableResult
    public func update(_ record: SessionRecord) async throws -> Bool {
        guard !Task.isCancelled, Self.isValidID(record.id), !deleted.contains(record.id) else { return false }
        _ = try load()
        requestSerial += 1
        requests[record.id] = requestSerial
        return try await embed(record, request: requestSerial) == .embedded
    }

    private enum Outcome { case unchanged, embedded, skipped }

    /// Accumulates privately across suspension and publishes only while this save still owns its record.
    private func embed(_ record: SessionRecord, request: Int) async throws -> Outcome {
        guard !Task.isCancelled, Self.isValidID(record.id), !deleted.contains(record.id),
              requests[record.id] == request else { return .skipped }
        let token = UUID()
        let generation = removals
        pending[record.id] = token
        defer { if pending[record.id] == token { pending[record.id] = nil } }
        func isOwned() -> Bool {
            !Task.isCancelled && removals == generation && pending[record.id] == token
                && requests[record.id] == request && !deleted.contains(record.id)
        }
        let chunks = HistoryChunker.chunks(for: record)
        let fingerprint = HistoryChunker.fingerprint(chunks, salt: embedder.signature)
        if catalog?[record.id]?.fingerprint == fingerprint { return .unchanged }
        // Passage identity includes text, source, language and embedding method, but not its
        // ordinal: adding a summary must not re-embed every unchanged transcript passage.
        let previous = vectorsOf(record.id)?.chunks ?? []
        var reusable = Dictionary(previous.map { ($0.fingerprint, $0) },
                                  uniquingKeysWith: { first, _ in first })
        var unavailable = Set<UInt64>()
        var vectors: [StoredChunkVector] = []
        for chunk in chunks {
            let passageFingerprint = HistoryChunker.fingerprint([chunk], salt: embedder.signature)
            if let stored = reusable[passageFingerprint] {
                vectors.append(StoredChunkVector(ordinal: chunk.ordinal, model: stored.model, scale: stored.scale,
                                                values: stored.values, fingerprint: passageFingerprint))
                continue
            }
            guard !unavailable.contains(passageFingerprint) else { continue }
            let embedded: HistoryVector?
            if let language = chunk.language {
                embedded = await embedder.embed(chunk.text, transcribedIn: language)
            } else {
                embedded = await embedder.embed(chunk.text)
            }
            guard isOwned() else { return .skipped }
            let vector = embedded.map { StoredChunkVector(ordinal: chunk.ordinal, vector: $0,
                                                         fingerprint: passageFingerprint) }
            if vector == nil { unavailable.insert(passageFingerprint) }
            reusable[passageFingerprint] = vector
            if let vector { vectors.append(vector) }
        }
        guard isOwned() else { return .skipped }
        try store(StoredRecordVectors(fingerprint: fingerprint, chunks: vectors), for: record.id)
        return .embedded
    }

    /// Drops one conversation's vectors (the conversation was deleted).
    public func remove(id: String) throws {
        removals += 1
        guard Self.isValidID(id) else { return }
        deleted.insert(id)
        _ = try load()
        try deleteFile(id)
    }

    /// Drops every vector (Clear history). The folder and its version marker stay. The IDs indexed
    /// until now are never embedded again; a conversation saved afterwards is.
    public func removeAll() throws {
        deleted.formUnion(requests.keys)
        deleted.formUnion((try? load().keys).map(Array.init) ?? [])
        try wipe()
    }

    /// Deletes every vector file; the conversations may be embedded again (rebuild).
    private func wipe() throws {
        removals += 1
        revision += 1
        pending.removeAll()
        // Invalidate memory even if storage removal fails partway; the next read reloads disk.
        defer { catalog = nil; cache = [:]; cachedBytes = 0 }
        try prepare()
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == Self.fileExtension {
            try fileManager.removeItem(at: url)
        }
    }

    /// Discards everything and embeds `records` from scratch.
    @discardableResult
    public func rebuild(_ records: [SessionRecord]) async throws -> HistoryIndexReport {
        try wipe()
        return try await sync(records)
    }

    // MARK: - Storage

    /// Creates the folder, keeps it out of backups and discards anything another index version or
    /// embedding method wrote.
    private func prepare() throws {
        try PrivateStorage.createDirectory(at: directory)
        try? PrivateStorage.setExcludedFromBackup(true, at: directory)
        let marker = directory.appendingPathComponent("index.json")
        let expected = Manifest(version: Self.version, embedder: embedder.signature)
        let saved = (try? Data(contentsOf: marker)).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        if saved == expected { return }
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == Self.fileExtension {
            try fileManager.removeItem(at: url)
        }
        try JSONEncoder().encode(expected).write(to: marker, options: PrivateStorage.writingOptions)
        catalog = [:]
        cache = [:]
        cachedBytes = 0
    }

    private struct Manifest: Codable, Equatable {
        let version: Int
        let embedder: String
    }

    /// Reads the folder once; later calls use the in-memory catalog. Damaged files are deleted, so
    /// the next sync embeds those conversations again.
    private func load() throws -> [String: (fingerprint: UInt64, models: Set<String>)] {
        if let catalog { return catalog }
        try prepare()
        if let catalog { return catalog }   // `prepare` just reset an outdated folder
        var found: [String: (fingerprint: UInt64, models: Set<String>)] = [:]
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == Self.fileExtension {
            let id = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url), let stored = HistoryIndexFile.decode(data) else {
                try? fileManager.removeItem(at: url)
                continue
            }
            found[id] = (stored.fingerprint, Set(stored.chunks.map(\.model)))
            remember(stored, for: id)
        }
        catalog = found
        return found
    }

    private func vectorsOf(_ id: String) -> StoredRecordVectors? {
        if let cached = cache[id] { return cached }
        guard let data = try? Data(contentsOf: location(id)) else { return nil }
        return HistoryIndexFile.decode(data)
    }

    private func store(_ vectors: StoredRecordVectors, for id: String) throws {
        _ = try load()
        try HistoryIndexFile.encode(vectors).write(to: location(id), options: PrivateStorage.writingOptions)
        forget(id)
        catalog?[id] = (vectors.fingerprint, Set(vectors.chunks.map(\.model)))
        remember(vectors, for: id)
        revision += 1
    }

    private func deleteFile(_ id: String) throws {
        revision += 1
        let url = location(id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        catalog?[id] = nil
        forget(id)
    }

    /// Keeps vectors in memory only while the total stays within the budget.
    private func remember(_ vectors: StoredRecordVectors, for id: String) {
        guard cachedBytes + vectors.byteCount <= memoryBudget else { return }
        cache[id] = vectors
        cachedBytes += vectors.byteCount
    }

    private func forget(_ id: String) {
        if let old = cache.removeValue(forKey: id) { cachedBytes -= old.byteCount }
    }

    private func location(_ id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension(Self.fileExtension)
    }

    /// The same rule the archive applies to file names, so an ID can never escape the folder.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Search and retrieval.
extension HistoryIndex {
    // MARK: - Search

    /// Hybrid search over `records` (the archive as the caller has it). Keyword matches are all
    /// kept; conversations found only by meaning are added within `HistoryRanking.Parameters`.
    /// Conversations whose language has no on-device model are found by keyword exactly as before.
    public func search(_ query: String, in records: [SessionRecord]) async -> [HistorySearchResult] {
        guard !Task.isCancelled else { return [] }
        let records = records.filter { !deleted.contains($0.id) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return records.sorted { $0.date > $1.date }
                .map { HistorySearchResult(record: $0, matchesWords: false, isRelated: false, snippet: nil) }
        }
        let terms = SessionSearch.fold(trimmed).split(whereSeparator: \.isWhitespace).map(String.init)
        let keyword = SessionSearch.search(records, query: trimmed)
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let observed = revision
        let scan = await semanticScan(trimmed, ids: Set(byID.keys))
        guard !Task.isCancelled, revision == observed else { return [] }

        // Validate stored text before taking each population's top score. Incomparable model
        // families retain their own admission statistics and combine only after admission.
        var rankings: [[String]] = []
        var relatedChunks: [String: HistoryChunk] = [:]
        var snippetRanks: [String: Int] = [:]
        for key in scan.keys.sorted() {
            guard let population = scan[key] else { continue }
            var current: [(id: String, score: Float)] = []
            var chunksByID: [String: HistoryChunk] = [:]
            for (id, hit) in population.best.sorted(by: { $0.value.score > $1.value.score }) {
                guard parameters.isRelevant(hit.score, typical: population.typical,
                                            sample: population.sample) else { break }
                guard let record = byID[id] else { continue }
                let chunks = HistoryChunker.chunks(for: record)
                guard isCurrent(id, chunks), chunks.indices.contains(hit.ordinal) else { continue }
                current.append((id, hit.score))
                chunksByID[id] = chunks[hit.ordinal]
            }
            let admitted = HistoryRanking.related(current, typical: population.typical,
                                                  sample: population.sample, parameters: parameters)
            rankings.append(admitted.map(\.id))
            for (rank, candidate) in admitted.enumerated() where rank < snippetRanks[candidate.id] ?? .max {
                snippetRanks[candidate.id] = rank
                relatedChunks[candidate.id] = chunksByID[candidate.id]
            }
        }
        let keywordIDs = Set(keyword.map(\.id))
        var semanticOnly = 0
        let related = HistoryRanking.fuse(groups: rankings, fusion: parameters.fusion).filter { candidate in
            if keywordIDs.contains(candidate.id) { return true }
            semanticOnly += 1
            return semanticOnly <= parameters.maxRelated
        }
        let relatedIDs = Set(related.map(\.id))
        let order = HistoryRanking.fuse(keyword: keyword.map(\.id), semantic: related.map(\.id),
                                        fusion: parameters.fusion)
        return order.compactMap { id in
            guard let record = byID[id] else { return nil }
            let words = keywordIDs.contains(id)
            let chunk = relatedIDs.contains(id) ? relatedChunks[id] : nil
            let snippet = words ? HistoryRanking.keywordSnippet(record, terms: terms)
                : chunk.map { HistorySnippet(source: $0.source, text: HistoryRanking.clipped($0.text)) }
            return HistorySearchResult(record: record, matchesWords: words, isRelated: chunk != nil, snippet: snippet)
        }
    }

    /// The passages most relevant to `question`, at most `perConversation` from any one
    /// conversation. A passage qualifies when it holds all of the question's words (or two and at
    /// least half of them), or
    /// when its meaning passes the same relevance test as a "Related" search result; nothing below
    /// that is ever sent to a provider. Within each model population, rank by similarity plus the
    /// share of words it holds; independent populations combine by rank rather than raw cosine.
    public func retrieve(_ question: String, in records: [SessionRecord], limit: Int = 6,
                         perConversation: Int = 2) async -> [HistoryPassage] {
        guard !Task.isCancelled else { return [] }
        let records = records.filter { !deleted.contains($0.id) }
        let observed = revision
        let terms = HistoryQuestion.contentTerms(question)
        let queries = await queryVectors(question)
        guard !Task.isCancelled, revision == observed else { return [] }
        struct Candidate {
            let passage: HistoryPassage
            let words: Float
            let meaning: Float?
            let group: String?
        }
        var candidates: [Candidate] = []
        for record in records {
            let chunks = HistoryChunker.chunks(for: record)
            var vectors: [Int: StoredChunkVector] = [:]
            if !queries.isEmpty, isCurrent(record.id, chunks), let stored = vectorsOf(record.id) {
                for chunk in stored.chunks { vectors[chunk.ordinal] = chunk }
            }
            for chunk in chunks {
                let folded = SessionSearch.fold(chunk.text)
                let words = terms.isEmpty ? 0 : Float(terms.filter { folded.contains($0) }.count) / Float(terms.count)
                let meaning = vectors[chunk.ordinal].flatMap { stored in queries[stored.model].map(stored.similarity) }
                let passage = HistoryPassage(recordID: record.id, title: record.title, date: record.date,
                                             source: chunk.source, ordinal: chunk.ordinal, text: chunk.text,
                                             score: (meaning ?? 0) + words / 2)
                let group = meaning.flatMap { _ in vectors[chunk.ordinal].map { embedder.relevanceGroup(for: $0.model) } }
                candidates.append(Candidate(passage: passage, words: words, meaning: meaning, group: group))
            }
        }
        let populations = Dictionary(grouping: candidates.filter { $0.group != nil }, by: { $0.group! })
            .mapValues { candidates in
                let values = candidates.compactMap(\.meaning)
                return (typical: values.reduce(0, +) / Float(values.count),
                        top: values.max() ?? 0, sample: values.count)
            }
        let relevant = candidates.filter { candidate in
            // Words: all of the question's, or at least two and half of them.
            let found = Int((candidate.words * Float(terms.count)).rounded())
            if candidate.words >= 1 || (found >= 2 && candidate.words >= 0.5) { return true }
            guard let meaning = candidate.meaning, let group = candidate.group,
                  let population = populations[group] else { return false }
            return parameters.isRelevant(meaning, typical: population.typical, sample: population.sample)
                && meaning >= population.top - parameters.margin
        }
        func precedes(_ lhs: HistoryPassage, _ rhs: HistoryPassage) -> Bool {
            lhs.score == rhs.score ? (lhs.date, lhs.ordinal) > (rhs.date, rhs.ordinal) : lhs.score > rhs.score
        }
        let ordered: [HistoryPassage]
        if populations.count <= 1 {
            ordered = relevant.map(\.passage).sorted(by: precedes)
        } else {
            let groups = Dictionary(grouping: relevant) { $0.group.map { "model:" + $0 } ?? "words" }
            let rankings = groups.keys.sorted().map { key in
                (groups[key] ?? []).map(\.passage).sorted { lhs, rhs in
                    if lhs.score == rhs.score, lhs.date == rhs.date, lhs.ordinal == rhs.ordinal {
                        return lhs.id < rhs.id
                    }
                    return precedes(lhs, rhs)
                }.map(\.id)
            }
            let byID = Dictionary(relevant.map { ($0.passage.id, $0.passage) }, uniquingKeysWith: { first, _ in first })
            ordered = HistoryRanking.fuse(groups: rankings, fusion: parameters.fusion).compactMap { ranked in
                guard let passage = byID[ranked.id] else { return nil }
                return HistoryPassage(recordID: passage.recordID, title: passage.title, date: passage.date,
                                      source: passage.source, ordinal: passage.ordinal, text: passage.text,
                                      score: Float(ranked.score))
            }
        }
        var taken: [String: Int] = [:]
        var result: [HistoryPassage] = []
        for passage in ordered where result.count < limit {
            guard taken[passage.recordID, default: 0] < perConversation else { continue }
            taken[passage.recordID, default: 0] += 1
            result.append(passage)
        }
        return result
    }

    /// Whether the stored vectors were computed from exactly these chunks.
    private func isCurrent(_ id: String, _ chunks: [HistoryChunk]) -> Bool {
        catalog?[id]?.fingerprint == HistoryChunker.fingerprint(chunks, salt: embedder.signature)
    }

    /// Best passage per conversation and score population. The legacy population is unchanged.
    private struct Scan {
        var best: [String: (score: Float, ordinal: Int)] = [:]
        var total: Float = 0
        var sample = 0
        var typical: Float { sample == 0 ? 0 : total / Float(sample) }
    }

    private func semanticScan(_ query: String, ids: Set<String>) async -> [String: Scan] {
        let queries = await queryVectors(query)
        guard !queries.isEmpty, let catalog else { return [:] }
        var scans: [String: Scan] = [:]
        for id in catalog.keys where ids.contains(id) {
            guard let stored = vectorsOf(id) else { continue }
            for chunk in stored.chunks {
                guard let query = queries[chunk.model] else { continue }
                let score = chunk.similarity(query)
                let group = embedder.relevanceGroup(for: chunk.model)
                scans[group, default: Scan()].total += score
                scans[group, default: Scan()].sample += 1
                if score > scans[group]?.best[id]?.score ?? -.infinity {
                    scans[group, default: Scan()].best[id] = (score, chunk.ordinal)
                }
            }
        }
        return scans
    }

    /// One query vector per stored model the query plausibly belongs to.
    private func queryVectors(_ query: String) async -> [String: [Float]] {
        guard let catalog = try? load() else { return [:] }
        let models = catalog.values.reduce(into: Set<String>()) { $0.formUnion($1.models) }
        guard !models.isEmpty else { return [:] }
        var result: [String: [Float]] = [:]
        for vector in await embedder.embedQuery(query, models: models) { result[vector.model] = vector.values }
        return result
    }
}
