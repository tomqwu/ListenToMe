import Foundation
import ListenToMeCore

extension MobileSession {
    /// Labels before transcription saves/deletes chunks. The live microphone run is never restarted.
    /// Model failures are optional-label failures; transcription and its recovery remain available.
    func watchSpeakerLabels(_ chunks: [WatchAudioChunk], recordID: String,
                            recordingID: UUID) async throws -> WatchSpeakerLabels {
        let existing = history.first { $0.id == recordID }?.segments ?? []
        var labels = watchSpeakerContexts[recordingID] ?? WatchSpeakerLabels(existing: existing)
        labels.refreshNames(existing)
        guard speakers.enabled else {
            watchSpeakerContexts[recordingID] = nil
            return WatchSpeakerLabels(existing: existing)
        }
        // Wait only for work already requested by foreground setup, never initiate a download here.
        while speakers.preparation != nil, speakers.enabled {
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        guard speakers.enabled, speakers.modelsReady, !speakers.isUnavailable else { return labels }
        defer {
            if !Task.isCancelled, speakers.enabled, watchInbox.ledger(recordingID) != nil {
                watchSpeakerContexts[recordingID] = labels
            } else {
                watchSpeakerContexts[recordingID] = nil
            }
        }
        let audio = WatchSpeakerAudio(chunks: chunks)
        do {
            while let window = try await audio.next() {
                try Task.checkCancellation()
                guard let result = try await speakers.analyzeFileWindow(window.samples) else { break }
                labels.append(result, at: window.start)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Keep any successful windows. Uncovered lines retain the Apple Watch device label.
        }
        try Task.checkCancellation()
        return labels
    }
}

/// Only lightweight label metadata survives a window; voiceprints live in this unfinished recording only.
struct WatchSpeakerLabels {
    private var tracker: SpeakerIdentityTracker
    private var timeline: [DiarizedSegment] = []
    private var identities: [String: SpeakerIdentity] = [:]

    init(existing: [TranscriptSegment]) {
        tracker = SpeakerIdentityTracker(namespace: "watch:" + UUID().uuidString,
                                         firstNumber: SpeakerLabeling.nextSpeakerNumber(after: existing))
    }

    mutating func refreshNames(_ existing: [TranscriptSegment]) {
        for line in existing {
            guard let id = line.speakerID, let name = line.speakerName, identities[id] != nil else { continue }
            tracker.rename(id: id, name: name)
            identities[id]?.name = name
        }
    }

    mutating func append(_ window: DiarizedWindow, at start: TimeInterval) {
        let shifted = window.segments.map {
            DiarizedSegment(speakerId: $0.speakerId, start: $0.start + start, duration: $0.duration)
        }
        let mapping = tracker.reconcile(shifted, since: start, embeddings: window.embeddings)
        for identity in mapping.values { identities[identity.id] = identity }
        let identified = shifted.compactMap { segment in
            mapping[segment.speakerId].map {
                DiarizedSegment(speakerId: $0.id, start: segment.start, duration: segment.duration)
            }
        }
        timeline = SpeakerStats.splice(history: timeline, window: identified, windowStart: start)
    }

    @MainActor func label(_ segment: TranscriptSegment) -> TranscriptSegment {
        var result = segment
        let assigned = SpeakerLabeling.assign(transcript: [segment], diarized: timeline, identities: identities,
                                              offset: 0, source: .you, minimumCoverage: MobileSpeakers.minimumCoverage)
        if let identity = assigned[segment.id] {
            result.speakerID = identity.id
            result.speakerName = identity.name
        }
        return result
    }
}
