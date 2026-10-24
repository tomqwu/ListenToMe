import Foundation
import Tokenizers
@testable import ListenToMeIOS
import XCTest

final class MobileLanguageTokenizerTests: XCTestCase {
    /// Minimal vocabulary extracted from openai/whisper-tiny tokenizer.json, SHA256
    /// 27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566. Preserves actual token IDs.
    func testCachedTokenizerUsesEncodedSpaceAndLanguageTokens() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = Bundle(for: Self.self)
        for (source, target) in [("watch-tokenizer", "tokenizer.json"),
                                 ("watch-tokenizer-config", "tokenizer_config.json")] {
            let url = try XCTUnwrap(bundle.url(forResource: source, withExtension: "json"))
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(target))
        }
        let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
        XCTAssertNil(tokenizer.convertTokenToId(" "))
        let adapter = try MobileLanguageTokenizer(tokenizer)
        XCTAssertEqual(adapter.specialTokens.whitespaceToken, 220)
        XCTAssertEqual(adapter.specialTokens.startOfTranscriptToken, 50258)
        XCTAssertTrue(adapter.allLanguageTokens.contains(50260))
        XCTAssertEqual(adapter.convertIdToToken(50260), "<|zh|>")
    }
}
