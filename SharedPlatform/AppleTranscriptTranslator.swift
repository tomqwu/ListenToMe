import Foundation
import NaturalLanguage
// TranslationSession exposes cancel during async translation but has no Sendable annotation.
// Both request entry points below remain MainActor-isolated.
@preconcurrency import Translation
import ListenToMeCore

/// Native installed-pack adapter. Only the explicit SwiftUI preparation control may request packs.
@MainActor final class AppleTranscriptTranslator: TranscriptTranslating {
    enum PackStatus { case installed, downloadRequired, unsupported }
    struct NativeSession {
        var translate: @MainActor (String) async throws -> String
        var cancel: @MainActor () -> Void
    }
    struct Environment {
        var status: @MainActor (String, String) async -> PackStatus
        var makeSession: @MainActor (String, String) -> NativeSession
        init(status: @escaping @MainActor (String, String) async -> PackStatus,
             makeSession: @escaping @MainActor (String, String) -> NativeSession) {
            self.status = status; self.makeSession = makeSession
        }
        init(status: @escaping @MainActor (String, String) async -> PackStatus,
             run: @escaping @MainActor (String, String, String) async throws -> String) {
            self.init(status: status, makeSession: { source, target in
                NativeSession(translate: { text in try await run(text, source, target) }, cancel: {})
            })
        }
        static var device: Self {
            Self(status: { source, target in
                let availability = LanguageAvailability()
                switch await availability.status(from: .init(identifier: source), to: .init(identifier: target)) {
                case .installed: return .installed
                case .supported: return .downloadRequired
                default: return .unsupported
                }
            }, makeSession: { source, target in
                let session = TranslationSession(installedSource: .init(identifier: source),
                                                 target: .init(identifier: target))
                return NativeSession(translate: { text in try await session.translate(text).targetText },
                                     cancel: { session.cancel() })
            })
        }
    }
    private let environment: Environment
    private struct Request {
        let id: UUID
        var session: NativeSession?
        var cancelled = false
    }
    private var request: Request?
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
        guard request == nil else {
            throw Unavailable(reason: "The previous translation is still stopping. Retry when it finishes.")
        }
        let id = UUID()
        request = Request(id: id)
        // Cancellation fences the request but cannot free an operation still using native resources.
        defer { if request?.id == id { request = nil } }
        return try await withTaskCancellationHandler {
            do {
                // Packs may have been removed since UI readiness. This factory uses installedSource
                // only, so translation itself cannot request downloads or send text to a provider.
                let readiness = await availability(source: source, target: target)
                try checkCurrent(id)
                guard readiness.canRun else {
                    throw Unavailable(reason: readiness.reason ?? "Translation is unavailable.")
                }
                let session = environment.makeSession(source, target)
                request?.session = session
                let result = try await session.translate(text)
                try checkCurrent(id)
                return result
            } catch {
                try checkCurrent(id)
                throw error
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancel(requestID: id) }
        }
    }
    func cancel() {
        if let id = request?.id { cancel(requestID: id) }
    }
    private func cancel(requestID: UUID) {
        guard request?.id == requestID, request?.cancelled == false else { return }
        request?.cancelled = true
        request?.session?.cancel()
    }
    private func checkCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard request?.id == id, request?.cancelled == false else { throw CancellationError() }
    }
    private struct Unavailable: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
}
