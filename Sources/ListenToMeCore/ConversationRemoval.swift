import Foundation

/// Deletes the archive first, then every registered kind of owned data. If the archive cannot be
/// removed, owners are left untouched so a still-visible conversation does not lose its audio.
public enum ConversationRemoval {
    public struct Result: Sendable, Equatable {
        public let archiveWarning: String?
        public let failedOwners: [String]
    }

    public static func remove(_ record: SessionRecord, from archive: SessionArchive,
                              owners: [ConversationDataOwner]) throws -> Result {
        let warning = try archive.delete(id: record.id)
        let failures = ConversationDataErasure.run(owners, for: ConversationDeletion(records: [record]))
        return Result(archiveWarning: warning, failedOwners: failures)
    }
}
