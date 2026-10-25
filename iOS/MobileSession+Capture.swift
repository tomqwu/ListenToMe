import Foundation
import ListenToMeCore
import UIKit

/// Platform adapter: Core owns task lifetime and transition ordering; this owns device policy.
extension MobileSession {
    func start() {
        guard state == .idle, !isSummarizing, captureCoordinator.phase == .idle else { return }
        captureCoordinator.phaseChanged = { [weak self] in self?.state = $0 }
        captureCoordinator.start { token in
            message = nil; stopReason = nil
            speechCorrection.cancel(); acceptsSpeechCorrection = true
            if let partial { segments.append(partial); self.partial = nil }
            let recorder = makeRecorder(); self.recorder = recorder
            let offset = segments.map(\.end).max() ?? 0
            attachRunAudio(to: recorder, offset: offset)
            let drain = watchDrainTask
            drain?.cancel()
            return CaptureCoordinator.Operations(prepare: { [weak self] in
                await drain?.value
                try Task.checkCancellation()
                guard let self else { throw CancellationError() }
                await recorder.setContextualStrings(self.vocabularyRecognitionTerms)
            }, start: { [weak self] in
                guard let self else { throw CancellationError() }
                try await recorder.start(locale: Locale(identifier: self.recordingLanguage)) { [weak self] segment in
                    guard let self, self.captureCoordinator.acceptsEvents(from: token) else { return }
                    self.receiveCaptureSegment(segment, offset: offset)
                } onFailure: { [weak self] error in
                    guard let self, self.captureCoordinator.acceptsEvents(from: token),
                          self.state == .recording || self.state == .preparing else { return }
                    self.message = error
                    Task { await self.stop() }
                }
            }, stop: {
                try await recorder.stop()
            }, didStart: { [weak self] in
                guard let self else { return }
                UIApplication.shared.isIdleTimerDisabled = true
                self.startRecognitionLoops()
            }, didFinish: { [weak self] error, wasRecording in
                self?.finishCapture(error: error, wasRecording: wasRecording)
            })
        }
    }

    func stop() async {
        if state == .recording {
            languageDetection.activityLoop?.cancel(); languageDetection.activityLoop = nil
            if stopReason == nil { stopReason = .user }
        }
        await captureCoordinator.stop()
    }

    private func finishCapture(error: Error?, wasRecording: Bool) {
        recorder = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if let error {
            message = wasRecording ? "Could not finalize transcript: \(error.localizedDescription)"
                : error.localizedDescription
        }
        if !wasRecording { speakers.endRun() }
        save(announce: false)
        if wasRecording { nameConversationIfNeeded(); finishSpeakerIdentification() }
        endLanguageRun(); endSavedAudioRun()
    }
}
