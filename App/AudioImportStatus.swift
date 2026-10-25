import Observation

@MainActor @Observable
final class AudioImportStatus {
    private(set) var fileName = ""
    private(set) var fraction = 0.0
    var cancelling = false
    var progressLabel: String {
        fraction >= 1 ? "Finalizing transcript…" : "\(Int(fraction * 100))% read"
    }
    func begin(fileName: String) {
        self.fileName = fileName
        fraction = 0
        cancelling = false
    }
    func update(_ fraction: Double) { self.fraction = fraction }
}
