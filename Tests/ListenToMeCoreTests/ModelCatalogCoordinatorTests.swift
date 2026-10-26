import XCTest
@testable import ListenToMeCore

@MainActor
final class ModelCatalogCoordinatorTests: XCTestCase {
    func testAIOffNeverQueriesACatalogOrChangesModelChoices() async {
        let coordinator = ModelCatalogCoordinator()
        var calls = 0
        var update: ModelCatalogCoordinator.Update?
        await coordinator.reload(configuration: { .init(mode: .off, destination: "off") },
                                 choices: { [.quick: .init(model: "Keep my choice", pinned: true)] },
                                 discover: { calls += 1; return .init(names: ["Unrequested"]) },
                                 apply: { update = $0 }).value
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(update?.status, "AI is off")
        XCTAssertTrue(update?.discovery.names.isEmpty == true)
        XCTAssertTrue(update?.choices.isEmpty == true, "AI-off must not heal or persist any model choice")
    }

    func testChangedRouteRejectsOldCatalogWithoutWaitingForAnotherRefresh() async {
        for next in [ModelCatalogCoordinator.Configuration(mode: .off, destination: "off"),
                     .init(mode: .openAI, destination: "Second server")] {
            let coordinator = ModelCatalogCoordinator()
            var route = ModelCatalogCoordinator.Configuration(mode: .openAI, destination: "First server")
            var reply: CheckedContinuation<ModelCatalogCoordinator.Discovery, Never>?
            var updates = 0
            let work = coordinator.reload(configuration: { route }, choices: { [:] }, discover: {
                await withCheckedContinuation { reply = $0 }
            }, apply: { _ in updates += 1 })
            await waitForReply { reply != nil }
            route = next
            reply?.resume(returning: .init(names: ["Obsolete model"], problem: "Obsolete status"))
            await work.value
            XCTAssertEqual(updates, 0, "Settings may change before another refresh starts")
        }
    }

    func testCancelledRefreshCannotPublishItsLateCatalog() async {
        let coordinator = ModelCatalogCoordinator()
        var reply: CheckedContinuation<ModelCatalogCoordinator.Discovery, Never>?
        var updates = 0
        let work = coordinator.reload(configuration: { .init(mode: .local, destination: "local") },
                                      choices: { [:] }, discover: {
            await withCheckedContinuation { reply = $0 }
        }, apply: { _ in updates += 1 })
        await waitForReply { reply != nil }
        work.cancel()
        reply?.resume(returning: .init(names: ["Obsolete local choice"]))
        await work.value
        XCTAssertEqual(updates, 0)
    }

    func testCancellationBeforeExecutionNeverQueriesCatalog() async {
        for mode in [AIProcessingMode.local, .apple] {
            let coordinator = ModelCatalogCoordinator()
            var calls = 0, updates = 0
            let work = coordinator.reload(configuration: { .init(mode: mode, destination: "selected") },
                                          choices: { [:] }, discover: { calls += 1; return .init() },
                                          apply: { _ in updates += 1 })
            coordinator.cancel()
            await work.value
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(updates, 0)
        }
    }

    func testNewerRefreshKeepsItsModelChoicesWhenAnOlderReplyArrives() async {
        let coordinator = ModelCatalogCoordinator()
        var reply: CheckedContinuation<ModelCatalogCoordinator.Discovery, Never>?
        var applied: [String] = []
        let old = coordinator.reload(configuration: { .init(mode: .local, destination: "local") },
                                     choices: { [:] }, discover: {
            await withCheckedContinuation { reply = $0 }
        }, apply: { applied += $0.discovery.names })
        await waitForReply { reply != nil }
        await coordinator.reload(configuration: { .init(mode: .local, destination: "local") },
                                 choices: { [:] }, discover: {
            .init(names: ["Current model"], verifiedLocal: ["Current model"])
        }, apply: { applied += $0.discovery.names }).value
        reply?.resume(returning: .init(names: ["Old model"]))
        await old.value
        XCTAssertEqual(applied, ["Current model"])
    }

    private func waitForReply(_ ready: () -> Bool) async {
        for _ in 0..<200 {
            if ready() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Injected catalog did not start")
    }

    func testVerifiedLocalDefaultsExcludeCloudModels() async {
        let coordinator = ModelCatalogCoordinator()
        var update: ModelCatalogCoordinator.Update?
        await coordinator.reload(configuration: { .init(mode: .local, destination: "local") }, choices: { [:] },
                                 discover: {
            .init(names: ["remote-pro:cloud", "local:3b", "local:7b"],
                  verifiedLocal: ["local:3b", "local:7b"])
        }, apply: { update = $0 }).value
        XCTAssertEqual(update?.choices[.quick]?.model, "local:3b")
        XCTAssertEqual(update?.choices[.deep]?.model, "local:7b")
        XCTAssertFalse(update?.choices.values.contains(where: { $0.model.contains("cloud") }) ?? true)
        XCTAssertTrue(update?.choices[.quick]?.persist == true)
    }

    func testPinnedChoiceSurvivesInconclusiveCatalog() async {
        let coordinator = ModelCatalogCoordinator()
        var update: ModelCatalogCoordinator.Update?
        await coordinator.reload(configuration: { .init(mode: .local, destination: "local") },
                                 choices: { [.quick: .init(model: "My selected model", pinned: true)] },
                                 discover: { .init(catalogFailed: true, problem: "Catalog unavailable") },
                                 apply: { update = $0 }).value
        XCTAssertEqual(update?.choices[.quick]?.model, "My selected model")
        XCTAssertFalse(update?.choices[.quick]?.persist ?? true)
        XCTAssertEqual(update?.status, "Catalog unavailable")
    }

    func testCloudAndCustomCatalogsKeepModelChoiceExplicit() async {
        for mode in [AIProcessingMode.openAI, .cloudAI] {
            let coordinator = ModelCatalogCoordinator()
            var update: ModelCatalogCoordinator.Update?
            await coordinator.reload(configuration: { .init(mode: mode, destination: "Chosen server") },
                                     choices: { [.quick: .init(model: "chosen", pinned: true)] },
                                     discover: { .init(names: ["chosen", "unselected"]) },
                                     apply: { update = $0 }).value
            XCTAssertEqual(update?.choices[.quick]?.model, "chosen")
            XCTAssertEqual(update?.choices[.deep]?.model, "")
            XCTAssertFalse(update?.choices.values.contains(where: \.persist) ?? true)
            XCTAssertTrue(update?.status.contains("Choose a model") == true)
        }
    }

    func testAppleIntelligenceNeverRequestsACatalog() async {
        let coordinator = ModelCatalogCoordinator()
        var calls = 0
        var update: ModelCatalogCoordinator.Update?
        await coordinator.reload(configuration: {
            .init(mode: .apple, destination: "on-device", appleUnavailableReason: "Enable Apple Intelligence")
        }, choices: { [:] }, discover: { calls += 1; return .init() }, apply: { update = $0 }).value
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(update?.discovery.names, ["Apple Intelligence"])
        XCTAssertEqual(update?.status, "Enable Apple Intelligence")
        XCTAssertEqual(update?.choices.count, 3)
        XCTAssertFalse(update?.choices.values.contains(where: \.persist) ?? true)
    }
}
