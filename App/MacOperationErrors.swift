import Foundation
import Observation

/// Capture and file operations own separate visible recovery messages.
@MainActor @Observable
final class MacOperationErrors {
    var capture: String?
    var file: String?

    func importFailed(_ error: Error) {
        file = "Couldn't import this recording: \(error.localizedDescription)"
    }
}
