import XCTest
import NaturalLanguage
@testable import ListenToMeCore

final class VocabularyChineseTests: XCTestCase {
    private let catalog = VocabularyCatalog.bundled.localized(for: "zh-CN")
    static let speech: [String: String] = [
        "medical": "患者存在心房颤动和心力衰竭，服用美托洛尔和阿哌沙班。检查肌钙蛋白、肌酐和超声心动图，评估射血分数。",
        "legal": "合同需要明确不可抗力、违约责任、诉讼时效、举证责任、管辖权和仲裁条款。我们正在审查保密协议和竞业限制。",
        "software-cloud": "我们需要容器编排和持续集成，改进负载均衡、服务发现、链路追踪和日志聚合。先进行灰度发布，再检查回滚策略。",
        "engineering": "设计评审需要有限元分析，检查公差配合、尺寸链、表面粗糙度和应力集中。评估疲劳寿命、屈服强度和弹性模量。",
        "finance": "我们检查现金流量表、资产负债表和利润表，分析应收账款、递延收入、营业成本和毛利率，预测自由现金流。",
        "sales": "根据销售漏斗检查商机阶段和潜在客户。确认决策链和采购流程，再做需求挖掘、产品演示和报价单，讨论成交概率。",
        "education-research": "研究假设需要文献综述和理论框架。明确自变量、因变量、混杂变量和样本量，报告置信区间、效应量和统计功效。"
    ]

    func testEveryPresetHasAnOriginalValidatedChineseListAndStableIdentity() throws {
        XCTAssertEqual(catalog.languageIdentifier, "zh-Hans")
        for original in VocabularyCatalog.bundled.domains {
            let translated = try XCTUnwrap(catalog.domain(id: original.id))
            XCTAssertGreaterThanOrEqual(translated.terms.count, 50)
            XCTAssertEqual(translated.terms, original.simplifiedChinese?.terms)
            XCTAssertEqual(translated.name, original.name)
            XCTAssertEqual(translated.notice, original.notice)
            XCTAssertEqual(translated.summaryLayout, original.summaryLayout)
            XCTAssertNotEqual(translated.description, original.description)
            XCTAssertEqual(Set(translated.terms).count, translated.terms.count)
        }
        for locale in ["zh", "zh_CN", "zh-SG", "zh-Hans", "zh-Hans-CN"] {
            XCTAssertEqual(VocabularyCatalog.bundled.localized(for: locale), catalog, locale)
        }
        for locale in ["en-US", "fr-FR", "ja-JP", "zh-Hant", "zh-TW", "zh-HK"] {
            XCTAssertEqual(VocabularyCatalog.bundled.localized(for: locale), .bundled, locale)
        }
    }

    func testChinesePresetsReachRecognitionAndPromptWithoutChangingMyTerms() {
        let active = ActiveVocabulary(settings: VocabularySettings(defaultDomainIDs: ["medical"], myTerms: ["Acme", "张伟"]),
                                      catalog: catalog)
        let recognition = active.recognitionTerms()
        XCTAssertEqual(Array(recognition.prefix(2)), ["张伟", "Acme"])
        XCTAssertTrue(recognition.contains("心房颤动"))
        XCTAssertFalse(recognition.contains("metoprolol"))
        XCTAssertLessThanOrEqual(recognition.count, ActiveVocabulary.recognitionLimit)
        XCTAssertTrue(VocabularyPrompt.guidance(for: active)?.contains("心房颤动") == true)
        XCTAssertTrue(active.domains.first?.notice?.contains("not a medical device") == true)
    }

    func testContinuousChineseAndCodeSwitchedSpeechSuggestTheCorrectDomainWithoutAnEmbedding() {
        let classifier = VocabularyClassifier(catalog: catalog, similarity: nil)
        for (id, sentence) in Self.speech {
            let speech = String(repeating: sentence, count: 10)
            XCTAssertGreaterThanOrEqual(VocabularyClassifier.wordCount(speech), VocabularyClassifier.minimumWords)
            XCTAssertEqual(classifier.suggestion(for: speech), id, id)
            XCTAssertEqual(classifier.scores(for: speech).max { $0.weightedHits < $1.weightedHits }?.id, id)
        }
        XCTAssertGreaterThanOrEqual(classifier.scores(for: "用Kubernetes实现容器编排和灰度发布")
            .first { $0.id == "software-cloud" }?.distinctTerms ?? 0, 3)
        XCTAssertNil(classifier.suggestion(for: String(repeating: "我们今天去公园散步，晚上一起吃饭，明天接孩子放学。", count: 30)))
        XCTAssertNil(classifier.suggestion(for: Self.speech["medical"]!))
    }

    func testChineseCorrectionGlossaryFindsTermsAndNearMissesInsideSentences() {
        let active = ActiveVocabulary(settings: VocabularySettings(defaultDomainIDs: ["medical"], myTerms: ["张伟"]),
                                      catalog: catalog)
        let index = VocabularyPrompt.CorrectionIndex(active)
        let glossary = index.glossary(for: "张伟说患者存在心房颤动和呼吸困难，需要检查肌钙蛋白。")
        for term in ["张伟", "心房颤动", "呼吸困难", "肌钙蛋白"] { XCTAssertTrue(glossary.contains(term), term) }
        XCTAssertTrue(index.glossary(for: "患者出现心房颤冻，需要观察。").contains("心房颤动"))
        XCTAssertFalse(index.glossary(for: "我们今天去公园散步。").contains("心房颤动"))
    }

    func testChineseWindowDropsOldTermsEvenWithoutSpaces() {
        let classifier = VocabularyClassifier(catalog: catalog, similarity: nil)
        let long = Self.speech["medical"]! + String(repeating: "我们今天去公园散步，晚上一起吃饭，明天接孩子放学。", count: 250)
        XCTAssertEqual(classifier.scores(for: long).first { $0.id == "medical" }?.distinctTerms, 0)
    }

    func testChineseEmbeddingIsUsedWhenAvailableAndOtherwiseFallsBackToTerms() {
        let similarity = SentenceEmbeddingSimilarity(language: .simplifiedChinese)
        if NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) == nil {
            XCTAssertNil(similarity.similarity("病史", "临床医疗"))
            XCTAssertNil(VocabularyClassifier(catalog: catalog).embeddingRanking(for: "临床医疗"))
        } else {
            XCTAssertNotNil(similarity.similarity("病史", "临床医疗"))
            XCTAssertNotNil(VocabularyClassifier(catalog: catalog).embeddingRanking(for: "临床医疗"))
        }
    }

    func testInvalidTranslationsAreRejectedWithoutBreakingOldFiles() throws {
        let source = try XCTUnwrap(VocabularyCatalog.bundled.domain(id: "medical"))
        func invalid(_ translation: VocabularyTranslation) -> VocabularyDomain {
            VocabularyDomain(id: source.id, name: source.name, description: source.description,
                             summaryLayout: source.summaryLayout, terms: source.terms, simplifiedChinese: translation)
        }
        XCTAssertTrue(VocabularyCatalog.problems(in: invalid(.init(description: "", terms: [])))
            .contains { $0.contains("description") })
        XCTAssertTrue(VocabularyCatalog.problems(in: invalid(.init(description: "临床", terms: [])))
            .contains { $0.contains("50") })
        XCTAssertTrue(VocabularyCatalog.problems(in: invalid(.init(description: "临床", terms: [" ", "重复", "重复"])))
            .contains { $0.contains("invalid Simplified") })
        XCTAssertTrue(VocabularyCatalog.problems(in: invalid(.init(description: "临床", terms: ["重复", "重复"])))
            .contains { $0.contains("duplicate Simplified") })
        let old = VocabularyDomain(id: source.id, name: source.name, description: source.description,
                                   summaryLayout: source.summaryLayout, terms: source.terms)
        let decoded = try VocabularyCatalog.decode(JSONEncoder().encode(old))
        XCTAssertNil(decoded.simplifiedChinese)
        XCTAssertEqual(VocabularyCatalog(domains: [old]).localized(for: "zh-CN").domains, [old])
    }
}
