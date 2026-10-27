import Foundation
import NaturalLanguage
import Translation
import ListenToMeCore

/// Native installed-pack adapter. Only the explicit SwiftUI preparation control may request packs.
@MainActor final class AppleTranscriptTranslator: TranscriptTranslating {
    enum PackStatus { case installed, downloadRequired, unsupported }
    struct Environment {
        var status: @MainActor (String, String) async -> PackStatus
        var run: @MainActor (String, String, String) async throws -> String
        static var device: Self {
            Self(status: { source, target in
                switch await LanguageAvailability().status(from: .init(identifier: source), to: .init(identifier: target)) {
                case .installed: return .installed
                case .supported: return .downloadRequired
                default: return .unsupported
                }
            }, run: { text, source, target in
                let session = TranslationSession(installedSource: .init(identifier: source), target: .init(identifier: target))
                let response = try await session.translate(text)
                return response.targetText
            })
        }
    }
    private let environment: Environment
    init(environment: Environment = .device) { self.environment = environment }
    func sourceLanguage(for text: String, hint: String?) -> String? {
        if let hint, !["", "auto", "automatic", "und"].contains(hint.lowercased()),
           hint.count <= 64, hint.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
           let code = Locale(identifier: hint).language.languageCode?.identifier, code != "und" {
            return Locale(identifier: hint).identifier(.bcp47)
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(10_000)))
        return recognizer.dominantLanguage?.rawValue
    }
    func availability(source: String, target: String) async -> FeatureAvailability {
        switch await environment.status(source, target) {
        case .installed: return .ready
        case .downloadRequired:
            return .setupRequired(reason: "Download the selected translation languages on this device first.",
                                  action: "Prepare languages")
        case .unsupported:
            return .unsupported(reason: "On-device translation does not support this language pair on this device.")
        }
    }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        try Task.checkCancellation()
        // Packs may have been removed since the UI checked readiness. Never let the native session
        // request assets: `installedSource` cannot request downloads or send content to a provider.
        let readiness = await availability(source: source, target: target)
        try Task.checkCancellation()
        guard readiness.canRun else { throw Unavailable(reason: readiness.reason ?? "Translation is unavailable.") }
        let text = try await environment.run(text, source, target)
        try Task.checkCancellation()
        return text
    }
    // Cancellation of the caller's Task propagates to the native request. Core also fences results
    // and keeps its single worker slot until an uncooperative framework call actually returns.
    func cancel() {}
    private struct Unavailable: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
}
