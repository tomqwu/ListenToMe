import AVFoundation
import Foundation
import ListenToMeCore
import WhisperKit

extension MobileSession {
    /// Pin once, before any words are saved. A retry must not reinterpret the remaining audio after
    /// Settings changes or a model download. Older manifests inherit the saved transcript's locale.
    func watchTranscriptionLocale(_ ledger: WatchCaptureLedger, chunks: [WatchAudioChunk],
                                  recordID: String) async throws -> String {
        if let pinned = ledger.transcriptionLocale { return pinned }
        let saved = history.first { $0.id == recordID }
        let prior = saved?.segments?.first { $0.language != nil }?.language ?? saved?.language
        var chosen = prior ?? transcriptionLanguage
        if prior == nil, ledger.transcribedThrough == 0, languageDetection.automatic,
           let model = languageDetection.model {
            do {
                if try await model.prepareIfDownloaded() {
                    let samples = try await watchLanguageSamples(chunks)
                    try Task.checkCancellation()
                    if samples.count >= LanguageDetectionPolicy.sampleRate * Int(LanguageDetectionPolicy.minimumSpeech) {
                        let guess = try await model.detect(samples: samples)
                        let supported = await model.supportedLocales()
                        if case .switchTo(let locale) = LanguageDetectionPolicy.decide(
                            detected: guess.language, probability: guess.probability, current: chosen,
                            supported: supported, pinned: false, atSwitchLimit: false,
                            region: Locale.current.region?.identifier) {
                            chosen = locale
                        }
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Detection is optional. The normal file transcriber still reports unreadable audio.
            }
        }
        try Task.checkCancellation()
        guard let pinned = try watchInbox.update(ledger.recordingID, { entry in
            entry.pinTranscriptionLocale(chosen)
            return entry.transcriptionLocale
        }) else { throw CancellationError() }
        return pinned ?? chosen
    }
}

/// Bounded decoding off the UI actor; uses the same conversion path as Watch transcription.
enum WatchLanguageAudio {
    static func samples(_ chunks: [WatchAudioChunk]) async throws -> [Float] {
        let task = Task.detached {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else { return [Float]() }
            let feed = ChunkFeed(chunks: chunks, format: format)
            let limit = LanguageDetectionPolicy.sampleRate * Int(LanguageDetectionPolicy.maximumWindow)
            var samples: [Float] = []
            var inspected = 0
            // A five-minute scan handles a quiet start without scanning an hours-long recording.
            let scanLimit = LanguageDetectionPolicy.sampleRate * 300
            let detector = EnergyVAD()
            while samples.count < limit, inspected < scanLimit, let input = feed.next() {
                try Task.checkCancellation()
                let buffer = input.buffer
                guard let channel = buffer.floatChannelData?[0] else { continue }
                let audio = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                inspected += audio.count
                let activity = detector.voiceActivity(in: audio)
                for (index, voiced) in activity.enumerated() where voiced {
                    let start = index * detector.frameLengthSamples
                    let end = min(audio.count, start + detector.frameLengthSamples, start + limit - samples.count)
                    if end > start { samples.append(contentsOf: audio[start..<end]) }
                }
            }
            if let error = feed.failure { throw error }
            return samples
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
