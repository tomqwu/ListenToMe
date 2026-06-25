import XCTest
@testable import ListenToMeCore

final class ModelRankingTests: XCTestCase {
    func testWeightOrdersByParameterSize() {
        XCTAssertLessThan(ModelRanking.weight("gemma3:4b"), ModelRanking.weight("gemma3:12b"))
        XCTAssertLessThan(ModelRanking.weight("llama3.1:8b"), ModelRanking.weight("llama3.1:70b"))
        XCTAssertLessThan(ModelRanking.weight("qwen2.5:1.5b"), ModelRanking.weight("qwen2.5:7b"))
    }

    func testWeightBoostsCoderAndProAndReasoning() {
        XCTAssertGreaterThan(ModelRanking.weight("qwen3-coder:30b"), ModelRanking.weight("qwen3:30b"))
        XCTAssertGreaterThan(ModelRanking.weight("deepseek-v4-pro"), ModelRanking.weight("deepseek-v4"))
        XCTAssertGreaterThan(ModelRanking.weight("deepseek-r1:7b"), ModelRanking.weight("deepseek:7b"))
    }

    func testWeightLowersFastModels() {
        XCTAssertLessThan(ModelRanking.weight("deepseek-v4-flash"), ModelRanking.weight("deepseek-v4"))
        XCTAssertLessThan(ModelRanking.weight("phi3-mini"), ModelRanking.weight("phi3"))
    }

    func testRankedAscendingWithStableTieBreak() {
        // Two zero-weight, no-size names tie on weight -> ordered by name.
        XCTAssertEqual(ModelRanking.ranked(["zeta", "alpha"]), ["alpha", "zeta"])
    }

    func testRoleDefaultsEmptyForNoModels() {
        XCTAssertTrue(ModelRanking.roleDefaults(from: []).isEmpty)
        XCTAssertNil(ModelRanking.defaultModel(for: .quick, from: []))
    }

    func testRoleDefaultsSingleModelReusedAcrossRoles() {
        let defaults = ModelRanking.roleDefaults(from: ["gemma3:12b"])
        XCTAssertEqual(defaults[.quick], "gemma3:12b")
        XCTAssertEqual(defaults[.listener], "gemma3:12b")
        XCTAssertEqual(defaults[.deep], "gemma3:12b")
    }

    func testRoleDefaultsAssignsDistinctModelsWhenAvailable() {
        // flash (light) < gemma3:12b (mid) < qwen3-coder:30b (heavy, coder boost).
        let models = ["gemma3:12b", "deepseek-v4-flash", "qwen3-coder:30b"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.quick], "deepseek-v4-flash")
        XCTAssertEqual(defaults[.listener], "gemma3:12b")
        XCTAssertEqual(defaults[.deep], "qwen3-coder:30b")
    }

    func testRoleDefaultsTwoModels() {
        // ranked: [flash, 70b]; middle index (2-1)/2 = 0 -> listener == quick.
        let defaults = ModelRanking.roleDefaults(from: ["llama3.1:70b", "llama3.1-flash:8b"])
        XCTAssertEqual(defaults[.quick], "llama3.1-flash:8b")
        XCTAssertEqual(defaults[.listener], "llama3.1-flash:8b")
        XCTAssertEqual(defaults[.deep], "llama3.1:70b")
    }

    func testRoleDefaultsPrefersLocalOverCloud() {
        // The cloud flash model is "lighter" but must NOT be auto-picked while a local model
        // exists — auto-defaults stay local-first to avoid silently sending transcripts to cloud.
        let models = ["llama3.1:8b", "deepseek-v4-flash:cloud"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.quick], "llama3.1:8b")
        XCTAssertEqual(defaults[.deep], "llama3.1:8b")
        XCTAssertFalse(defaults.values.contains { $0.contains(":cloud") })
    }

    func testRoleDefaultsUsesCloudOnlyWhenNoLocal() {
        let models = ["deepseek-v4-flash:cloud", "deepseek-v4-pro:cloud"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.quick], "deepseek-v4-flash:cloud")
        XCTAssertEqual(defaults[.deep], "deepseek-v4-pro:cloud")
    }

    func testRoleDefaultsPrefersProFlagshipForDeepOverLargerModels() {
        // Realistic Ollama Cloud list: Deep should pick the curated "pro" flagship, NOT the model
        // with the largest parameter count; Quick should pick the "flash" model.
        let models = [
            "mistral-large-3:675b", "qwen3-coder:480b", "deepseek-v4-pro",
            "deepseek-v4-flash", "gemma3:12b", "gemini-3-flash-preview"
        ]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.deep], "deepseek-v4-pro")
        XCTAssertEqual(defaults[.quick], "deepseek-v4-flash")
        // Listener is a balanced middle pick, distinct from Quick and Deep.
        XCTAssertNotEqual(defaults[.listener], defaults[.quick])
        XCTAssertNotEqual(defaults[.listener], defaults[.deep])
    }

    func testRoleDefaultsKeepsQuickAndDeepDistinctForDualTaggedModel() {
        // "deepseek-coder-v2-lite:16b" matches both a fast pattern ("lite") and a strong one
        // ("coder"); with another model present, Quick and Deep must not collapse onto it.
        let models = ["deepseek-coder-v2-lite:16b", "llama3.1:70b"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.quick], "deepseek-coder-v2-lite:16b")
        XCTAssertEqual(defaults[.deep], "llama3.1:70b")
        XCTAssertNotEqual(defaults[.quick], defaults[.deep])
    }

    func testGeminiProNotMisreadAsFastMiniModel() {
        // "gemini" must NOT match the "mini" fast marker (token-boundary matching). The Pro model
        // is the strong/Deep pick; the lighter 8B llama is Quick.
        let models = ["gemini-3-pro-preview", "llama3.1:8b"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.quick], "llama3.1:8b")
        XCTAssertEqual(defaults[.deep], "gemini-3-pro-preview")
        XCTAssertGreaterThan(
            ModelRanking.weight("gemini-3-pro-preview"), ModelRanking.weight("llama3.1:8b"))
    }

    func testMarkerVariantsMatchByTokenPrefix() {
        // Variant marker forms still count: "codellama"/"codegemma" ~ "code", "reasoning" ~
        // "reason". These models should weigh as strong and win the Deep pane.
        XCTAssertGreaterThan(ModelRanking.weight("codellama:13b"), ModelRanking.weight("llama3:13b"))
        XCTAssertGreaterThan(
            ModelRanking.weight("phi4-reasoning:14b"), ModelRanking.weight("phi4:14b"))
        XCTAssertEqual(ModelRanking.roleDefaults(from: ["codellama:13b", "gemma3:27b"])[.deep],
                       "codellama:13b")
    }

    func testListenerDefaultPrefersSecondFastModelNotHeavyOne() {
        // Two flash models + a heavy one: Listener (continuous refresh) should take the second
        // flash, NOT the heavy glm model.
        let models = ["deepseek-v4-flash", "gemini-3-flash-preview", "glm-5.2", "deepseek-v4-pro"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.quick], "deepseek-v4-flash")
        XCTAssertEqual(defaults[.deep], "deepseek-v4-pro")
        XCTAssertEqual(defaults[.listener], "gemini-3-flash-preview")
    }

    func testListenerFallsBackToLightestRemainingWhenNoSecondFast() {
        // No second fast model available -> Listener takes the lightest of what's left.
        let models = ["deepseek-v4-flash", "glm-5.2", "deepseek-v4-pro"]
        let defaults = ModelRanking.roleDefaults(from: models)
        XCTAssertEqual(defaults[.listener], "glm-5.2")
    }

    func testDescribeUsesCuratedHintsMostSpecificFirst() {
        XCTAssertEqual(ModelRanking.describe("deepseek-v4-pro"), "competitive coding & reasoning")
        XCTAssertEqual(ModelRanking.describe("deepseek-v4-flash"), "fast, cost-efficient")
        XCTAssertEqual(ModelRanking.describe("deepseek-v3.1:671b"), "strong reasoning")
        XCTAssertEqual(ModelRanking.describe("glm-5.1"), "long-horizon agentic")
        XCTAssertEqual(ModelRanking.describe("glm-5.2"), "agentic, self-host")
        XCTAssertEqual(ModelRanking.describe("qwen3-coder:480b"), "repo-level coding")
    }

    func testDescribeFallsBackToCapabilityHeuristic() {
        XCTAssertEqual(ModelRanking.describe("codellama:13b"), "coding")
        XCTAssertEqual(ModelRanking.describe("somemodel-reasoning:14b"), "strong reasoning")
        XCTAssertEqual(ModelRanking.describe("acme-flash:7b"), "fast")
        XCTAssertEqual(ModelRanking.describe("acme:7b"), "general")
    }

    func testDefaultModelForRoleMatchesRoleDefaults() {
        let models = ["gemma3:12b", "deepseek-v4-flash", "qwen3-coder:30b"]
        XCTAssertEqual(ModelRanking.defaultModel(for: .deep, from: models), "qwen3-coder:30b")
        XCTAssertEqual(ModelRanking.defaultModel(for: .quick, from: models), "deepseek-v4-flash")
    }
}
