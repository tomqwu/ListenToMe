import SwiftUI
import AVFoundation

@main
struct ListenToMeIOSApp: App {
    /// The app is the only place the language model is created; tests get a stand-in that downloads nothing.
    @State private var session = MobileSession(makeLanguageModel: WhisperLanguageIdentifier.deviceModel)
    /// Active before any scene exists, so a watch message that launches the app in the background is
    /// answered (with "open the iPhone app") instead of reaching the microphone (issue #181).
    private let watchLink: PhoneWatchLink?

    init() {
        try? ConversationExportFile.removeAll()   // an export file is never kept past this app run
        watchLink = PhoneWatchLink.activateIfSupported(inbox: WatchInbox(root: WatchInbox.defaultRoot))
    }

    var body: some Scene {
        WindowGroup {
            meeting
                .tint(MobileStyle.accent)
                .task {
                    session.importSharedInbox()
                    session.tidySavedAudio()   // killed runs repaired, orphaned audio deleted (#55)
                    attachWatchLink()
                    session.importWatchInbox()
                }
                // The transcription languages this device supports, read once for Settings (issue #172).
                .task { await SpeechLanguageCatalog.shared.load() }
                .onOpenURL { session.importFile($0) }
                .onChange(of: session.busy) { _, busy in
                    guard !busy else { return }
                    session.importSharedInbox()
                    session.importWatchInbox()
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                    guard let event = MobileSession.interruption(from: note) else { return }
                    Task { await session.handleInterruption(event.type, options: event.options) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                    guard let reason = MobileSession.routeChangeReason(from: note) else { return }
                    Task { await session.handleRouteChange(reason) }
                }
        }
    }

    private func attachWatchLink() {
        guard let watchLink else { return }
        let session = session
        watchLink.commandHandler = { await session.handleWatchCommand($0) }
        // Audio is filed on arrival in any app state; it is transcribed only in the foreground.
        watchLink.onInboxChanged = { session.importWatchInbox() }
        // Shown only: "Apple Watch is recording · …". The phone records nothing in this mode.
        watchLink.onWatchContext = { session.receiveWatchContext($0) }
        session.receiveWatchContext(watchLink.receivedWatchContext)
        session.watchLink = watchLink
        session.publishWatchStatus()
    }

    @ViewBuilder private var meeting: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--recording-continuity-fixture") {
            MobileRecordingContinuityFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--start-failure-fixture") {
            MobileStartFailureFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--incremental-summary-fixture") {
            MobileIncrementalSummaryFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--speech-correction-fixture") {
            MobileCorrectionFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--automatic-summary-fixture") {
            MobileAutomaticSummaryFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--transcript-scroll-fixture") {
            MobileTranscriptFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--language-activity-fixture") {
            MobileLanguageActivityFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--watch-speakers-fixture") {
            MobileWatchSpeakerFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--saved-audio-fixture") {
            MobileSavedAudioFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--design-review-fixture") {
            MobileDesignFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--selection-summary-fixture") {
            MobileSelectionSummaryFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--vocabulary-fixture") {
            MobileVocabularyFixture()
        } else {
            MobileMeetingView(session: session).mobileSessionLifecycle(session)
        }
        #else
        MobileMeetingView(session: session).mobileSessionLifecycle(session)
        #endif
    }
}
