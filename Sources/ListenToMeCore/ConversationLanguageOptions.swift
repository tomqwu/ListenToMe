import Foundation

/// Language choices are conversation metadata. Translations are a derived, on-device display;
/// original transcript text remains authoritative for search, exports, audio timing and AI grounding.
public struct ConversationLanguageOptions: Codable, Equatable, Hashable, Sendable {
    public var translateTranscript: Bool
    public var translationTarget: String
    public var summaryTranslationTarget: String
    public init(translateTranscript: Bool = false, translationTarget: String = "en",
                summaryTranslationTarget: String = "en") {
        self.translateTranscript = translateTranscript
        self.translationTarget = translationTarget
        self.summaryTranslationTarget = summaryTranslationTarget
    }
    private enum CodingKeys: CodingKey { case translateTranscript, translationTarget, summaryTranslationTarget }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        translateTranscript = try values.decodeIfPresent(Bool.self, forKey: .translateTranscript) ?? false
        translationTarget = try values.decodeIfPresent(String.self, forKey: .translationTarget) ?? "en"
        summaryTranslationTarget = try values.decodeIfPresent(String.self, forKey: .summaryTranslationTarget) ?? "en"
    }
}

/// Output language choices are independent of transcription support. Apple Translation checks the
/// exact source/target pair at runtime; AI providers keep their own availability and quality limits.
public struct OutputLanguage: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public var label: String { name }
    public static let all: [Self] = [
        .init(id: "en", name: "English"),
        .init(id: "zh-Hans", name: "Simplified Chinese"), .init(id: "zh-Hant", name: "Traditional Chinese"),
        .init(id: "ja", name: "Japanese"), .init(id: "ko", name: "Korean"),
        .init(id: "es", name: "Spanish"), .init(id: "fr", name: "French"), .init(id: "de", name: "German"),
        .init(id: "it", name: "Italian"), .init(id: "pt", name: "Portuguese"),
        .init(id: "ar", name: "Arabic"), .init(id: "hi", name: "Hindi"), .init(id: "ru", name: "Russian")
    ]
    public static func option(_ id: String) -> Self? { all.first { $0.id == id } }
}
