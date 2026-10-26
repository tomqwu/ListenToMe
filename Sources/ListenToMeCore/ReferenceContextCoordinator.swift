import Foundation
import Observation

/// Owns local attachment reads and the bounded grounding result supplied to a conversation.
@MainActor @Observable
public final class ReferenceContextCoordinator {
    public struct Update: Sendable {
        public let context: String?
        public let skipped: [TextFileReader.Skipped]
    }

    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    public init() {}

    @discardableResult
    public func load(_ urls: [URL], maxChars: Int,
                     apply: @escaping @MainActor (Update) -> Void) -> Task<Void, Never> {
        load(urls, maxChars: maxChars, read: { urls in
            await Task.detached { FileContextLoader.load(urls) }.value
        }, apply: apply)
    }

    @discardableResult
    public func load(_ urls: [URL], maxChars: Int,
                     read: @escaping @Sendable ([URL]) async -> FileContextLoader.Result,
                     apply: @escaping @MainActor (Update) -> Void) -> Task<Void, Never> {
        cancel()
        let token = generation
        let work = Task {
            defer { if generation == token { task = nil } }
            guard !Task.isCancelled, token == generation else { return }
            let result = await read(urls)
            guard !Task.isCancelled, token == generation else { return }
            apply(Update(context: ReferenceBuilder.build(documents: result.documents, maxChars: maxChars),
                         skipped: result.skipped))
        }
        task = work
        return work
    }

    /// Synchronous local file I/O already in progress may finish, but cannot publish after cancel.
    public func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
    }
}
