import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileCaptureCoordinatorTests: XCTestCase {
    private let keys = ["autoQuickSummary", MobileSession.languageKey, MobileLanguageDetection.automaticKey,
                        MobileSpeakers.enabledKey, SavedAudioPolicy.enabledKey]
    private var saved: [Any?] = []
    private var root: URL!

    override func setUp() async throws {
        saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        for key in keys { UserDefaults.standard.set(false, forKey: key) }
        UserDefaults.standard.set("en_US", forKey: MobileSession.languageKey)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }

    func testOldRecorderCannotAppendOrStopTheNextRun() async throws {
        let old = CaptureTestRecorder(), next = CaptureTestRecorder()
        var recorders = [old, next]
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorders.removeFirst() })
        session.start()
        try await wait { session.state == .recording }
        old.send("first run")
        await session.stop()
        old.send("late while idle")
        session.start()
        try await wait { session.state == .recording }
        let count = session.speechEventCount
        old.send("late after restart")
        old.failure?("old recorder failure")
        await Task.yield()
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.speechEventCount, count)
        XCTAssertFalse(session.message?.contains("old recorder") ?? false)
        next.send("second run")
        await session.stop()
        XCTAssertEqual(session.segments.map(\.text), ["first run", "second run"])
    }

    func testConcurrentStopWaitsForFinalTextAndSavesCompleteRecord() async throws {
        let recorder = CaptureTestRecorder()
        recorder.holdStop = true
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        session.start()
        try await wait { session.state == .recording }
        let first = Task { await session.stop() }
        try await wait { recorder.stopContinuation != nil }
        let second = Task { await session.stop() }
        await Task.yield()
        XCTAssertEqual(session.state, .stopping)
        session.newConversation()
        XCTAssertEqual(recorder.stops, 1)
        recorder.send("final words during teardown")
        recorder.stopContinuation?.resume(); recorder.stopContinuation = nil
        await first.value; await second.value
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.segments.map(\.text), ["final words during teardown"])
        XCTAssertEqual(session.currentRecord.isComplete, true)
        let saved = try JSONDecoder().decode(SessionRecord.self,
            from: Data(contentsOf: root.appendingPathComponent("ActiveConversation.json")))
        XCTAssertEqual(saved.isComplete, true)
        XCTAssertEqual(saved.segments?.map(\.text), ["final words during teardown"])
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(predicate())
    }
}

@MainActor private final class CaptureTestRecorder: MobileRecording {
    var segment: (@MainActor (TranscriptSegment) -> Void)?
    var failure: (@MainActor (String) -> Void)?
    var holdStop = false
    var stops = 0
    var stopContinuation: CheckedContinuation<Void, Never>?
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        segment = onSegment; failure = onFailure
    }
    func stop() async throws {
        stops += 1
        if holdStop { await withCheckedContinuation { stopContinuation = $0 } }
    }
    func reconfigure() async throws {}
    func send(_ text: String) {
        segment?(TranscriptSegment(source: .you, text: text, isFinal: true, start: 0, end: 1))
    }
}
