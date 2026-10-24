import Foundation
import ListenToMeCore
import Tokenizers
import WhisperKit

/// A strictly local adapter used only for language identification. WhisperKit's bundled adapter
/// cannot be constructed publicly and its factory silently downloads when local loading fails.
struct MobileLanguageTokenizer: WhisperTokenizer {
    let tokenizer: any Tokenizer
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    init(_ tokenizer: any Tokenizer) throws {
        func token(_ text: String) throws -> Int {
            guard let id = tokenizer.convertTokenToId(text), tokenizer.convertIdToToken(id) == text else {
                throw RecordingError.message("The downloaded language tokenizer is incomplete.")
            }
            return id
        }
        self.tokenizer = tokenizer
        specialTokens = try SpecialTokens(
            endToken: token("<|endoftext|>"), englishToken: token("<|en|>"),
            noSpeechToken: token("<|nospeech|>"), noTimestampsToken: token("<|notimestamps|>"),
            specialTokenBegin: token("<|endoftext|>"), startOfPreviousToken: token("<|startofprev|>"),
            startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"),
            transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"), whitespaceToken: token("Ġ"))
        allLanguageTokens = Set(Constants.languages.values.compactMap { tokenizer.convertTokenToId("<|\($0)|>") })
    }

    func encode(text: String) -> [Int] { tokenizer.encode(text: text) }
    func decode(tokens: [Int]) -> String { tokenizer.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { tokenizer.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { tokenizer.convertIdToToken(id) }
    // Language detection never produces word timestamps. Preserve the whole token group if queried.
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        ([decode(tokens: tokenIds)], [tokenIds])
    }
}
