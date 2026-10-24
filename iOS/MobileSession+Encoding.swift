import Foundation

extension MobileSession {
    /// `save()` skips the write when a record's bytes are unchanged. Without sorted keys the encoder's
    /// key order can differ between two encodings of the same record, so an unchanged conversation was
    /// written again (and `MobileSaveCostTests` failed intermittently).
    static var recordEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
