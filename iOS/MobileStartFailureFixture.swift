#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// A compatible capture path can still fail while downloading its model.
struct MobileStartFailureFixture: View {
    @State private var session = MobileSession(storageDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("StartFailureUI-\(UUID())"), makeRecorder: { FixtureRecorder() })
    var body: some View { MobileMeetingView(session: session) }
}

@MainActor
private final class FixtureRecorder: MobileRecording {
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        throw RecordingError.message("The speech model could not be downloaded. Check your connection and try again.")
    }
    func stop() async throws {}
    func reconfigure() async throws {}
}
#endif
