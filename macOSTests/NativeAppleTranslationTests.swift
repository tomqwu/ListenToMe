import XCTest
import ListenToMeCore
#if os(iOS)
@testable import ListenToMeIOS
#endif

@MainActor
final class NativeAppleTranslationTests: XCTestCase {
    func testNativePairReadinessPreventsUnpreparedTranslationAndNeverSubstitutesLanguages() async {
        for status in [AppleTranscriptTranslator.PackStatus.downloadRequired, .unsupported] {
            var queries: [String] = []; var sent = false
            let adapter = AppleTranscriptTranslator(environment: .init(status: { source, target in
                queries.append(source + ":" + target); return status
            }, run: { _, _, _ in sent = true; return "Unexpected" }))
            let readiness = await adapter.availability(source: "en-US", target: "fr")
            XCTAssertFalse(readiness.canRun)
            XCTAssertNotNil(readiness.reason)
            if status == .downloadRequired { XCTAssertEqual(readiness.setupAction, "Prepare languages") }
            do { _ = try await adapter.translate("Good morning.", source: "en-US", target: "fr")
                XCTFail("An unprepared pair must never construct an installed-model request")
            } catch { /* The original transcript remains the user's source. */ }
            XCTAssertFalse(sent)
            XCTAssertEqual(queries, ["en-US:fr", "en-US:fr"])
        }
    }
    func testInstalledNativePairUsesExactOriginalTextAndExplicitTarget() async throws {
        var payload: [String] = []
        let adapter = AppleTranscriptTranslator(environment: .init(status: { _, _ in .installed },
            run: { text, source, target in payload = [text, source, target]; return "早上好。" }))
        let readiness = await adapter.availability(source: "en-US", target: "zh-Hans")
        XCTAssertTrue(readiness.canRun)
        let output = try await adapter.translate("Good morning.", source: "en-US", target: "zh-Hans")
        XCTAssertEqual(output, "早上好。"); XCTAssertEqual(payload, ["Good morning.", "en-US", "zh-Hans"])
        XCTAssertEqual(adapter.sourceLanguage(for: "An unrelated language.", hint: "zh-Hant"), "zh-Hant")
    }
    func testCancelFencesLateTextAndKeepsRequestOwnedUntilItReturns() async throws {
        let held = HeldNativeTranslation()
        var constructions = 0
        let adapter = AppleTranscriptTranslator(environment: .init(status: { _, _ in .installed },
            makeSession: { _, _ in constructions += 1; return held.session }))
        let request = Task { try await adapter.translate("Original summary.", source: "en-US", target: "zh-Hans") }
        await settle(); XCTAssertEqual(held.calls, ["Original summary."])
        adapter.cancel(); adapter.cancel()
        XCTAssertEqual(held.cancellations, 1, "Cancel must reach the owned native request exactly once")
        XCTAssertEqual(constructions, 1)
        held.release("过时的翻译。")
        assertCancelled(await request.result)
        let next = Task { try await adapter.translate("Current summary.", source: "en-US", target: "zh-Hans") }
        await settle(); XCTAssertEqual(constructions, 2, "The request slot becomes reusable only after exit")
        held.release("当前摘要。")
        let value = try await next.value; XCTAssertEqual(value, "当前摘要。")
    }
    func testConcurrentRequestCannotReplaceAnOwnedNativeRequest() async throws {
        let held = HeldNativeTranslation()
        var constructions = 0
        let adapter = AppleTranscriptTranslator(environment: .init(status: { _, _ in .installed },
            makeSession: { _, _ in
                constructions += 1
                return constructions == 1 ? held.session
                    : .init(translate: { _ in "Unexpected replacement" }, cancel: {})
            }))
        let first = Task { try await adapter.translate("Original.", source: "en", target: "zh-Hans") }
        await settle(); adapter.cancel()
        do {
            _ = try await adapter.translate("Replacement.", source: "en", target: "fr")
            XCTFail("Cancelling must not release a native request that has not returned")
        } catch { /* The occupied slot reports a recoverable refusal. */ }
        XCTAssertEqual(constructions, 1, "No native overlap is allowed")
        held.release("Late")
        assertCancelled(await first.result)
    }
    func testCallerCancellationReachesNativeRequest() async {
        let held = HeldNativeTranslation()
        let adapter = AppleTranscriptTranslator(environment: .init(status: { _, _ in .installed },
            makeSession: { _, _ in held.session }))
        let request = Task { try await adapter.translate("Original.", source: "en", target: "zh-Hans") }
        await settle(); XCTAssertEqual(held.calls.count, 1)
        request.cancel(); await settle()
        XCTAssertEqual(held.cancellations, 1, "Task cancellation must call the native session cancellation API")
        held.release("Late")
        assertCancelled(await request.result)
    }
    func testCancelledReadinessNeverConstructsNativeRequest() async {
        var continuation: CheckedContinuation<AppleTranscriptTranslator.PackStatus, Never>?
        var constructions = 0
        let adapter = AppleTranscriptTranslator(environment: .init(status: { _, _ in
            await withCheckedContinuation { continuation = $0 }
        }, makeSession: { _, _ in constructions += 1; return .init(translate: { _ in "Late" }, cancel: {}) }))
        let request = Task { try await adapter.translate("Original.", source: "en", target: "zh-Hans") }
        await settle(); XCTAssertNotNil(continuation)
        adapter.cancel()
        continuation?.resume(returning: .installed); continuation = nil
        assertCancelled(await request.result)
        XCTAssertEqual(constructions, 0, "A stale installed status cannot start a native model request")
    }
    private func settle() async { for _ in 0..<200 { await Task.yield() } }
    private func assertCancelled(_ result: Result<String, Error>, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success: XCTFail("Cancelled native text must never return as a successful result", file: file, line: line)
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Expected cancellation, got \(error)", file: file, line: line)
        }
    }

}

@MainActor private final class HeldNativeTranslation {
    var calls: [String] = []
    var cancellations = 0
    private var continuation: CheckedContinuation<String, Never>?
    var session: AppleTranscriptTranslator.NativeSession {
        .init(translate: { [self] text in
            calls.append(text)
            return await withCheckedContinuation { continuation = $0 }
        }, cancel: { [self] in cancellations += 1 })
    }
    func release(_ value: String) { continuation?.resume(returning: value); continuation = nil }
}
