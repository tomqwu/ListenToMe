import Foundation
import ListenToMeCore

/// View actions supply platform effects; the Core coordinator owns capture and restart tasks.
extension MeetingView {
    func toggleCapture(session: MeetingSession) {
        guard !lifecycleBusy, !isImporting else { return }
        if wantsCapture {
            captureStartGate.cancel()
            _ = checkpoint()
            recordingStartedAt = nil
            let stoppedRun = diarizationRunToken
            captureCoordinator.requestStop(after: {
                _ = checkpoint(complete: true, force: true)
                nameConversationIfNeeded()
            }, background: {
                await finishSpeakerAnalysis(expectedRun: stoppedRun)
            })
        } else {
            captureCoordinator.start { _ in captureOperations(session: session) }
        }
    }

    func restartForLocaleChange(session: MeetingSession) {
        captureCoordinator.restart { _ in captureOperations(session: session, checkPermission: false) }
    }

    private func captureOperations(session: MeetingSession, checkPermission: Bool = true)
        -> CaptureCoordinator.Operations {
        CaptureCoordinator.Operations(prepare: {
            startError = nil
            try await MacCapturePreflight.prepare(gate: captureStartGate, refresh: {
                await refreshFeatureAvailability()
                return recordingAvailability
            }, permission: checkPermission ? { await microphoneDecision() } : nil,
            blocked: { startError = $0 })
        }, start: {
            // Reset before starting; anchor after prior finals have drained and the new run is live.
            beginDiarizationRunReset()
            activeEngine = ProviderSettings.transcriptionEngine
            try await session.start()
        }, stop: {
            await session.stopAndWait()
            await MacSavedAudio.shared.waitForWrites()
        }, interrupt: {
            // MeetingSession owns a cancellable model-prepare task. Stop it before awaiting start.
            session.stop()
        }, didStart: {
            guard session.isRunning else { return }
            noteCaptureLanguage()
            anchorDiarizationRun()
            if recordingStartedAt == nil { now = Date(); recordingStartedAt = now }
        }, didFinish: { error, _ in
            activeEngine = nil
            if !wantsCapture { recordingStartedAt = nil }
            if let error { startError = error.localizedDescription }
        })
    }
    /// Resolve permission; capture ownership fences any late denial.
    func microphoneDecision() async -> CapturePreflight.Decision {
        var decision = CapturePreflight.decide(microphone: PermissionsModel.currentMicrophoneAuthorization())
        if decision == .requestAccess {
            let granted = await PermissionsModel.requestMicrophoneAccess()
            permissions.refresh()
            decision = CapturePreflight.decideAfterRequest(granted: granted)
        }
        return decision
    }


}
