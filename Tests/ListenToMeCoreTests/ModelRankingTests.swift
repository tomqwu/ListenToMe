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

    func testDefaultModelForRoleMatchesRoleDefaults() {
        let models = ["gemma3:12b", "deepseek-v4-flash", "qwen3-coder:30b"]
        XCTAssertEqual(ModelRanking.defaultModel(for: .deep, from: models), "qwen3-coder:30b")
        XCTAssertEqual(ModelRanking.defaultModel(for: .quick, from: models), "deepseek-v4-flash")
    }
}
