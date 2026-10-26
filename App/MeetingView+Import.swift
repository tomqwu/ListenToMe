import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

extension MeetingView {
    /// Imports audio or a movie audio track with the source selected in the file picker,
    /// using the currently-selected language. Independent of live recording.
    func importAudioFile(session: MeetingSession) {
        guard !isImporting, !lifecycleBusy, !wantsCapture else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose an audio or video recording to transcribe"
        let sourcePicker = NSSegmentedControl(labels: ["Others", "You"], trackingMode: .selectOne,
                                             target: nil, action: nil)
        sourcePicker.selectedSegment = 0
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Label imported speech as:"), sourcePicker])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.setFrameSize(NSSize(width: 390, height: 30))
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url,
              !isImporting, !lifecycleBusy, !wantsCapture else { return }
        let source: SpeakerSource = sourcePicker.selectedSegment == 1 ? .you : .others
        exportError = nil
        // Imports always use SpeechAnalyzer (it finalizes all fed audio, so fast-feeding a file is
        // lossless), regardless of the live-capture engine setting; the chosen language still applies.
        let locale = ProviderSettings.transcriptionLocale()
        noteCaptureLanguage(engine: "speechAnalyzer")
        importStatus.begin(fileName: url.lastPathComponent)
        let progress = importStatus
        importWork.begin(operation: {
            let producer = try await MediaFileChunkProducer.open(url: url, source: source)
            await session.transcribeAudio(
                nextChunk: {
                    let chunk = try await producer.next()
                    await progress.update(await producer.progress())
                    return chunk
                },
                transcriber: { SpeechAnalyzerTranscriber(locale: locale) as any Transcribing })
        }, failed: { operationErrors.importFailed($0) })
    }
}
