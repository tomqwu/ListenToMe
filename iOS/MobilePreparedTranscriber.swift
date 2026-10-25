import AVFoundation
import Speech

/// The two on-device SpeechAnalyzer modules expose different result types. Consume their native
/// sequences lazily, preserving text/finality/times without another producer task or result queue.
struct MobilePreparedTranscriber: Sendable {
    struct Result: Sendable {
        let text: AttributedString
        let isFinal: Bool
        let range: CMTimeRange
    }

    let module: any SpeechModule
    private let consumeResults: @MainActor @Sendable ((Result) throws -> Bool) async throws -> Bool

    /// True means natural exhaustion; false means the consumer intentionally stopped delivery.
    @MainActor
    func consume(_ deliver: (Result) throws -> Bool) async throws -> Bool {
        try await consumeResults(deliver)
    }

    init<Module: SpeechModule>(_ module: Module,
                              text: @escaping @Sendable (Module.Result) -> AttributedString) {
        self.module = module
        consumeResults = { deliver in
            var iterator = module.results.makeAsyncIterator()
            while true {
                try Task.checkCancellation()
                guard let value = try await iterator.next(isolation: #isolation) else { return true }
                try Task.checkCancellation()
                guard try deliver(Result(text: text(value), isFinal: value.isFinal, range: value.range)) else { return false }
            }
        }
    }
}
