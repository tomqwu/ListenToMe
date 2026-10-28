import Foundation
import ListenToMeCore

extension MobileSession {
    func startRecognitionLoops() {
        startSpeakerLoop()
        resumeLanguageAfterForeground()
    }

    /// Cheap scans of newly accepted audio keep Automatic alive even when the recognizer has no
    /// results. Model checks still follow the existing cadence, confidence and hysteresis policy.
    func startLanguageActivityLoop(interval: Duration = .seconds(5)) {
        languageDetection.activityLoop?.cancel()
        guard !languageDetection.checksSuspended, let token = languageDetection.run?.token else { languageDetection.activityLoop = nil; return }
        languageDetection.activityLoop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.state == .recording, self.languageDetection.isCurrent(token) else { return }
                await self.checkLanguageAudioActivity()
            }
        }
    }

    func checkLanguageAudioActivity() async {
        let detection = languageDetection
        guard state == .recording, isForeground, applicationIsActive(),
              detection.automatic || detection.replay != nil,
              !detection.checksSuspended, !detection.isUnavailable, let run = detection.run,
              run.buffer.sampleCount > run.activityThrough else { return }
        let buffer = run.buffer, cursor = run.activityThrough
        let scan = await Task.detached(priority: .utility) { () -> ([Range<TimeInterval>], Int) in
            let snapshot = buffer.snapshot(fromSample: cursor)
            let first = max(cursor, snapshot.startSample)
            let skip = min(snapshot.samples.count, first - snapshot.startSample)
            let count = (snapshot.samples.count - skip) / LanguageAudioActivity.frameSamples
                * LanguageAudioActivity.frameSamples
            let samples = Array(snapshot.samples[skip..<(skip + count)])
            return (LanguageAudioActivity.ranges(in: samples, startSample: first), first + count)
        }.value
        guard !Task.isCancelled, state == .recording, isForeground, applicationIsActive(),
              detection.isCurrent(run.token) else { return }
        let request = detection.noteAudioActivity(scan.0, through: scan.1, token: run.token)
        if let stalled = detection.stalledReplayRequest() {
            let work = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.recoverLanguageReplay(stalled)
            }
            detection.recovery = work
            await work.value
        } else if let request {
            detection.check = Task { [weak self] in await self?.checkLanguage(request) }
        }
    }
}
