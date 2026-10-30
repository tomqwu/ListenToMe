import NaturalLanguage
import XCTest
@testable import ListenToMeCore

/// Required local native capability checks; hosted Core CI does not install lexical assets.
final class MacHistoryContentEligibilityTests: XCTestCase {
    func testSpanishSmallTalkAndGenericQueryAreRejectedButTopicsRemainEligible() throws {
        guard NLTagger.availableTagSchemes(for: .word, language: .spanish).contains(.lexicalClass) else {
            XCTFail("Spanish lexical tagging is not installed on this runtime"); return
        }
        for text in ["Vale, sí. Bueno, eh, veamos. Claro, claro. Me parece bien.",
                     "¿Puedes oírme? Creo que tienes el micrófono silenciado. Sí, ahora te oigo."] {
            XCTAssertEqual(HistoryContentEligibility.evaluate(text, language: "es-ES", kind: .passage),
                           .insufficientContent, text)
        }
        XCTAssertEqual(HistoryContentEligibility.evaluate("qué decidimos", language: "es", kind: .query),
                       .insufficientContent)
        XCTAssertEqual(HistoryContentEligibility.evaluate(
            "Decidimos que lo haremos y luego veremos qué pasa la próxima vez.", language: "es", kind: .passage), .insufficientContent)
        XCTAssertEqual(HistoryContentEligibility.evaluate(
            "Los abogados revisaron el contrato del proveedor y la cláusula de responsabilidad.", language: "es", kind: .passage), .eligible)
        XCTAssertEqual(HistoryContentEligibility.evaluate("pasaporte", language: "es", kind: .query), .eligible)
        XCTAssertEqual(HistoryContentEligibility.evaluate("pasaporte", language: "es", kind: .passage),
                       .insufficientContent, "Passages retain the existing three-word minimum; queries require one")
    }

    func testUnavailableLexicalTagsRemainUnknownForFillerAndTopics() throws {
        let cases: [String: (String, String)] = [
            "de": ("Okay, ja. Also, äh, mal sehen.",
                   "Die Anwälte prüften den Lieferantenvertrag und die Haftungsklausel."),
            "ja": ("はい、そうですね。ええと、考えてみましょう。", "弁護士が取引先との契約と責任条項を確認しました。"),
            "ko": ("네, 그래요. 음, 어디 보자. 맞아요.", "변호사들이 공급업체 계약서와 책임 조항을 검토했습니다.")
        ]
        var observed = 0
        for (code, (filler, topic)) in cases {
            let language = NLLanguage(rawValue: code)
            guard !NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass) else {
                continue
            }
            observed += 1
            for text in [filler, topic] {
                XCTAssertEqual(HistoryContentEligibility.evaluate(text, language: code, kind: .passage), .unknown)
                XCTAssertEqual(HistoryContentEligibility.evaluate(text, language: code, kind: .query), .unknown)
            }
        }
        XCTAssertGreaterThan(observed, 0, "All sample languages now provide lexical tags; unavailable branch not exercised")
    }

    func testEnglishGenericNounsAndLanguageDetectionReuseExistingRules() throws {
        guard NLTagger.availableTagSchemes(for: .word, language: .english).contains(.lexicalClass) else {
            XCTFail("English lexical tagging is not installed on this runtime"); return
        }
        XCTAssertEqual(HistoryContentEligibility.evaluate(
            "The team has a plan for next week.", language: "en_US", kind: .passage),
                       .insufficientContent, "Existing English generic nouns carry no topic")
        XCTAssertEqual(HistoryContentEligibility.evaluate("what did we decide", language: "en", kind: .query),
                       .insufficientContent)
        XCTAssertEqual(HistoryContentEligibility.evaluate(
            "The lawyers reviewed the vendor contract and the liability clause.", kind: .passage), .eligible)
        XCTAssertEqual(HistoryContentEligibility.evaluate("  ", kind: .passage), .insufficientContent)
    }

    func testExplicitLanguageAndMultiwordQueriesRetainSpanishPolicy() throws {
        guard NLTagger.availableTagSchemes(for: .word, language: .spanish).contains(.lexicalClass) else {
            XCTFail("Spanish lexical tagging is not installed on this runtime"); return
        }
        XCTAssertEqual(HistoryContentEligibility.evaluate("pasaporte", language: "es", kind: .query), .eligible)
        XCTAssertEqual(HistoryContentEligibility.evaluate("sí", language: "es", kind: .query), .insufficientContent)
        XCTAssertEqual(HistoryContentEligibility.evaluate("qué decidimos", kind: .query), .insufficientContent,
                       "A real multiword generic query still uses supported lexical evidence")
    }
}
