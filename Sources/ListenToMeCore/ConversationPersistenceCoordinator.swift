import Foundation

/// Owns dirty-state acknowledgement and the archive → export → active-snapshot transaction.
/// Native adapters retain encoding, paths, protection/backup attributes and user-facing errors.
@MainActor
public final class ConversationPersistenceCoordinator {
    private var lastSavedData: Data?
    public init() {}

    public func save(_ data: Data, hasContent: Bool, wasArchived: Bool,
                     archive: () throws -> Void, archived: () -> Void,
                     activeSnapshot: () throws -> Void) throws {
        guard data != lastSavedData else { return }
        if hasContent || wasArchived {
            try archive()
            archived()
        }
        try activeSnapshot()
        // A partial failure must not suppress the next retry with identical bytes.
        lastSavedData = data
    }

    public func invalidate() { lastSavedData = nil }
}
