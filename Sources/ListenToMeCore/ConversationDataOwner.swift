import Foundation

/// The conversations being deleted, as every store that keeps data for them needs it (#220).
/// `everything` is true for Delete all conversations: an owner may then drop its whole store, which
/// also takes data an unreadable or missing record left behind.
public struct ConversationDeletion: Sendable, Equatable {
    public let ids: [String]
    /// Share-sheet and Apple Watch import keys of the deleted conversations (`SessionRecord.sourceImportID`).
    public let sourceImportIDs: [String]
    public let everything: Bool

    public init(ids: [String], sourceImportIDs: [String] = [], everything: Bool = false) {
        self.ids = Self.unique(ids)
        self.sourceImportIDs = Self.unique(sourceImportIDs)
        self.everything = everything
    }

    public init(records: [SessionRecord], everything: Bool = false) {
        self.init(ids: records.map(\.id), sourceImportIDs: records.compactMap(\.sourceImportID),
                  everything: everything)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// One kind of data a conversation owns besides its archive record: attachments, Apple Watch audio,
/// a Save to folder queue entry, saved audio, a search index entry. Deleting one conversation and
/// deleting all of them run the same list of owners, so a store added later is removed by both.
public struct ConversationDataOwner {
    /// Shown to the user when this owner's data could not be removed, e.g. "attachments".
    public let name: String
    public let remove: (ConversationDeletion) throws -> Void

    public init(_ name: String, remove: @escaping (ConversationDeletion) throws -> Void) {
        self.name = name
        self.remove = remove
    }
}

public enum ConversationDataErasure {
    /// Runs every owner, even after one fails: a failure to delete attachments must not leave the
    /// Apple Watch audio behind. Returns the names of the owners that failed, in order.
    public static func run(_ owners: [ConversationDataOwner], for deletion: ConversationDeletion) -> [String] {
        owners.compactMap { owner in
            do { try owner.remove(deletion); return nil } catch { return owner.name }
        }
    }

    /// The note shown after the archive records are gone but some owned data is not.
    public static func failureNote(_ failed: [String]) -> String? {
        guard !failed.isEmpty else { return nil }
        let names = ListFormatter.localizedString(byJoining: failed)
        return "The conversation text is deleted, but some \(names) could not be removed from this device."
    }
}
