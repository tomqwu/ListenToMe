import Foundation
import Observation
import ListenToMeCore

/// Native save status follows the durable write, while privacy refusal never assembles a record.
@MainActor @Observable
final class MacCheckpointController {
    let coordinator = ConversationCheckpointCoordinator()
    var message = "Not saved yet"
    var failed = false

    func checkpoint(allowed: Bool, hasContent: Bool, force: Bool,
                    makeKey: () -> SessionCheckpointKey, makeRecord: (Date) -> SessionRecord,
                    persist: (SessionRecord) -> Bool, errorText: () -> String?,
                    didSave: (SessionRecord) -> Void) -> Bool {
        let outcome = coordinator.checkpoint(allowed: allowed, hasContent: hasContent, force: force,
                                            makeKey: makeKey, makeRecord: makeRecord, persist: persist)
        switch outcome {
        case .disabled: return false
        case .empty, .unchanged: return true
        case .failed:
            message = errorText() ?? "Save failed. Retry or Export to keep this conversation."
            failed = true
            return false
        case .saved(let record):
            didSave(record)
            message = "Saved at " + Date().formatted(date: .omitted, time: .standard)
            failed = false
            return true
        }
    }
}
