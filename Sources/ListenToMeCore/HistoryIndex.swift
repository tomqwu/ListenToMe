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
/// - `sync` is incremental: only conversations whose text changed are embedded again, and a
///   conversation no longer in the archive loses its vectors. An actor, so all of it runs off the
///   main thread; vectors are held in memory only up to `memoryBudget` and read from disk beyond it.
public actor HistoryIndex {
    public static let version = 1
    public static let folderName = "Search Index"
    static let fileExtension = "vectors"

    public nonisolated let directory: URL
    private let embedder: any HistoryEmbedder
    private let memoryBudget: Int
    private let parameters: HistoryRanking.Parameters
    private let fileManager = FileManager.default
    /// Fingerprint and model tags of every stored conversation; nil until the folder was read.
    private var catalog: [String: (fingerprint: UInt64, models: Set<String>)]?
    private var cache: [String: StoredRecordVectors] = [:]
    private var cachedBytes = 0
    /// Bumped by every removal, so a sync that is still running with an older list of conversations
    /// stops before it can write vectors for one that was deleted meanwhile.
    private var removals = 0

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

    /// IDs that currently have vectors on disk.
    public func indexedIDs() throws -> Set<String> { Set(try load().keys) }

    // MARK: - Maintenance

    /// Brings the index in line with `records`: embeds new or changed conversations and drops the
    /// vectors of conversations that are gone. Cancellation stops between conversations.
    @discardableResult
    public func sync(_ records: [SessionRecord]) async throws -> HistoryIndexReport {
        let mine = removals
        var report = HistoryIndexReport()
        let wanted = Set(records.map(\.id))
        for id in try load().keys where !wanted.contains(id) {
            try deleteFile(id)
            report.removed += 1
        }
        for record in records {
            guard !Task.isCancelled, removals == mine else { break }
            switch try embed(record) {
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
    public func update(_ record: SessionRecord) throws -> Bool {
        _ = try load()
        return try embed(record) == .embedded
    }

    private enum Outcome { case unchanged, embedded, skipped }

    /// Synchronous from the fingerprint check to the write, so a deletion cannot slip in between.
    private func embed(_ record: SessionRecord) throws -> Outcome {
        guard Self.isValidID(record.id) else { return .skipped }
        let chunks = HistoryChunker.chunks(for: record)
        let fingerprint = HistoryChunker.fingerprint(chunks, salt: embedder.signature)
        if catalog?[record.id]?.fingerprint == fingerprint { return .unchanged }
        let vectors = chunks.compactMap { chunk in
            embedder.embed(chunk.text).map { StoredChunkVector(ordinal: chunk.ordinal, vector: $0) }
        }
        try store(StoredRecordVectors(fingerprint: fingerprint, chunks: vectors), for: record.id)
        return .embedded
    }

    /// Drops one conversation's vectors (the conversation was deleted).
    public func remove(id: String) throws {
        removals += 1
        guard Self.isValidID(id) else { return }
        _ = try load()
        try deleteFile(id)
    }

    /// Drops every vector (Clear history). The folder and its version marker stay.
    public func removeAll() throws {
        removals += 1
        try prepare()
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == Self.fileExtension {
            try fileManager.removeItem(at: url)
        }
        catalog = [:]
        cache = [:]
        cachedBytes = 0
    }

    /// Discards everything and embeds `records` from scratch.
    @discardableResult
    public func rebuild(_ records: [SessionRecord]) async throws -> HistoryIndexReport {
        try removeAll()
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
    }

    private func deleteFile(_ id: String) throws {
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
    public func search(_ query: String, in records: [SessionRecord]) -> [HistorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return records.sorted { $0.date > $1.date }
                .map { HistorySearchResult(record: $0, matchesWords: false, isRelated: false, snippet: nil) }
        }
        let terms = SessionSearch.fold(trimmed).split(whereSeparator: \.isWhitespace).map(String.init)
        let keyword = SessionSearch.search(records, query: trimmed)
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var best: [(id: String, score: Float)] = []
        var bestOrdinal: [String: Int] = [:]
        for (id, vectors) in semanticScan(trimmed, ids: Set(byID.keys)) {
            best.append((id, vectors.score))
            bestOrdinal[id] = vectors.ordinal
        }
        var related = HistoryRanking.related(best, parameters: parameters)
        // A passage is only trusted while the conversation still has the text it was computed from.
        var relatedChunks: [String: HistoryChunk] = [:]
        related = related.filter { candidate in
            guard let record = byID[candidate.id], let ordinal = bestOrdinal[candidate.id] else { return false }
            let chunks = HistoryChunker.chunks(for: record)
            guard isCurrent(record.id, chunks), chunks.indices.contains(ordinal) else { return false }
            relatedChunks[candidate.id] = chunks[ordinal]
            return true
        }
        let keywordIDs = Set(keyword.map(\.id))
        var semanticOnly = 0
        related = related.filter { candidate in
            if keywordIDs.contains(candidate.id) { return true }
            semanticOnly += 1
            return semanticOnly <= parameters.maxRelated
        }
        let order = HistoryRanking.fuse(keyword: keyword.map(\.id), semantic: related.map(\.id),
                                        fusion: parameters.fusion)
        return order.compactMap { id in
            guard let record = byID[id] else { return nil }
            let words = keywordIDs.contains(id)
            let snippet = words ? HistoryRanking.keywordSnippet(record, terms: terms)
                : relatedChunks[id].map { HistorySnippet(source: $0.source, text: HistoryRanking.clipped($0.text)) }
            return HistorySearchResult(record: record, matchesWords: words, isRelated: relatedChunks[id] != nil,
                                       snippet: snippet)
        }
    }

    /// The passages most relevant to `question`, at most `perConversation` from any one
    /// conversation. Ranked by on-device similarity plus the share of the question's words a passage
    /// contains, so a language without an embedding model still retrieves by its words.
    public func retrieve(_ question: String, in records: [SessionRecord], limit: Int = 6,
                         perConversation: Int = 2) -> [HistoryPassage] {
        let terms = HistoryQuestion.contentTerms(question)
        let queries = queryVectors(question)
        var passages: [HistoryPassage] = []
        var meaningOnly: Set<String> = []
        var bestMeaning: Float = 0
        for record in records {
            let chunks = HistoryChunker.chunks(for: record)
            var vectors: [Int: StoredChunkVector] = [:]
            if !queries.isEmpty, isCurrent(record.id, chunks), let stored = vectorsOf(record.id) {
                for chunk in stored.chunks { vectors[chunk.ordinal] = chunk }
            }
            for chunk in chunks {
                let folded = SessionSearch.fold(chunk.text)
                let found = terms.filter { folded.contains($0) }.count
                let words = terms.isEmpty ? 0 : Float(found) / Float(terms.count)
                let meaning = vectors[chunk.ordinal].flatMap { stored in
                    queries[stored.model].map { stored.similarity($0) }
                } ?? 0
                guard words > 0 || meaning >= parameters.floor else { continue }
                passages.append(HistoryPassage(recordID: record.id, title: record.title, date: record.date,
                                               source: chunk.source, ordinal: chunk.ordinal, text: chunk.text,
                                               score: meaning + words / 2))
                if words == 0 { meaningOnly.insert(passages[passages.count - 1].id) }
                bestMeaning = max(bestMeaning, meaning)
            }
        }
        // A passage found by meaning alone must be close to the best one, as in `search`.
        passages.removeAll { meaningOnly.contains($0.id) && $0.score < bestMeaning - parameters.margin }
        passages.sort { $0.score == $1.score ? ($0.date, $0.ordinal) > ($1.date, $1.ordinal) : $0.score > $1.score }
        var taken: [String: Int] = [:]
        var result: [HistoryPassage] = []
        for passage in passages where result.count < limit {
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

    /// Best passage (similarity and ordinal) of every indexed conversation in `ids`.
    private func semanticScan(_ query: String, ids: Set<String>) -> [String: (score: Float, ordinal: Int)] {
        let queries = queryVectors(query)
        guard !queries.isEmpty, let catalog else { return [:] }
        var best: [String: (score: Float, ordinal: Int)] = [:]
        for id in catalog.keys where ids.contains(id) {
            guard let stored = vectorsOf(id) else { continue }
            for chunk in stored.chunks {
                guard let query = queries[chunk.model] else { continue }
                let score = chunk.similarity(query)
                if score > best[id]?.score ?? -.infinity { best[id] = (score, chunk.ordinal) }
            }
        }
        return best
    }

    /// One query vector per stored model the query plausibly belongs to.
    private func queryVectors(_ query: String) -> [String: [Float]] {
        guard let catalog = try? load() else { return [:] }
        let models = catalog.values.reduce(into: Set<String>()) { $0.formUnion($1.models) }
        guard !models.isEmpty else { return [:] }
        var result: [String: [Float]] = [:]
        for vector in embedder.embedQuery(query, models: models) { result[vector.model] = vector.values }
        return result
    }
}
