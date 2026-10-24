import SwiftUI
import ListenToMeCore

/// Follow new speech until the reader deliberately scrolls away from the end.
struct MobileTranscriptReader: View {
    let segments: [TranscriptSegment]
    var scrollIdentifier = "transcriptScroll"
    var restoreOriginal: ((UUID) -> Void)?
    /// Shows who said each line once speaker identification has labeled any of them (issue #180).
    var showsSpeakers = false
    /// Where a line plays from in the saved audio (issue #55); `nil` hides the play controls.
    var audioTarget: ((TranscriptSegment) -> SavedAudioSeek.Target?)?
    var playAudio: ((SavedAudioSeek.Target) -> Void)?
    @State private var reviewing: TranscriptSegment?
    @State private var following = true
    @State private var readingSnapshot: [TranscriptSegment]?
    private var displayedSegments: [TranscriptSegment] { readingSnapshot ?? segments }
    @State private var userScrolling = false
    private let endID = "transcript-end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if displayedSegments.isEmpty {
                        Text("Start listening and your words will appear here.").foregroundStyle(.secondary)
                    }
                    ForEach(displayedSegments) { segment in
                        VStack(alignment: .leading, spacing: 5) {
                            if !segment.isFinal {
                                Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(MobileStyle.transcript)
                            }
                            if let target = audioTarget?(segment) {
                                Button(SavedAudioPolicy.timeLabel(segment.start), systemImage: "play.circle") {
                                    playAudio?(target)
                                }.font(.caption.monospacedDigit()).buttonStyle(.borderless)
                                    .accessibilityLabel("Play from \(SavedAudioPolicy.timeLabel(segment.start))")
                                    .accessibilityIdentifier("transcript-play-\(segment.id)")
                            }
                            if showsSpeakers {
                                Text(segment.speakerLabel).font(.caption.weight(.semibold))
                                    .foregroundStyle(segment.speakerID == nil ? MobileStyle.muted : MobileStyle.accent)
                                    .accessibilityIdentifier("transcript-speaker-\(segment.id)")
                            }
                            Text(segment.text).font(.body).lineSpacing(4).textSelection(.enabled)
                                .foregroundStyle(segment.isFinal ? .primary : .secondary)
                                .accessibilityIdentifier("transcript-text-\(segment.id)")
                            if segment.originalText != nil, restoreOriginal != nil {
                                Button("AI corrected", systemImage: "sparkles") { reviewing = segment }
                                    .font(.caption).buttonStyle(.borderless)
                                    .accessibilityIdentifier("review-correction-\(segment.id)")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(MobilePlayOnTap(target: audioTarget?(segment), play: playAudio))
                    }
                    Color.clear.frame(height: 1).id(endID)
                }.padding(16)
            }
            .accessibilityIdentifier(scrollIdentifier)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // Follow once after a text update. Scrolling inside a content-size geometry callback
            // can repeatedly invalidate layout when a correction badge changes a short viewport.
            .task(id: displayedSegments) {
                // Coalesce incoming hypotheses and let the stack resolve wrapped row heights.
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled else { return }
                if following && !userScrolling { proxy.scrollTo(endID, anchor: .bottom) }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let target = max(0, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
                // Wrapped rows can change the content height after an update. Align only
                // when actually displaced, including an offset beyond the newly resolved end.
                return abs(geometry.contentOffset.y - target) > 2 ? geometry.contentSize.height.rounded() : 0
            } action: { _, displacedHeight in
                guard displacedHeight > 0, following, !userScrolling else { return }
                Task { @MainActor in
                    await Task.yield()
                    if following && !userScrolling { proxy.scrollTo(endID, anchor: .bottom) }
                }
            }
            .onScrollGeometryChange(for: Bool.self) { nearEnd($0) } action: { _, atEnd in
                if userScrolling { following = atEnd }
            }
            // Freeze the reader's view while browsing history. Capture continues in `segments`,
            // but changing offscreen rows must not revise lazy heights beneath the reading position.
            .onChange(of: following) { _, follows in
                readingSnapshot = follows ? nil : segments
            }
            .onScrollPhaseChange { _, phase, context in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    userScrolling = true
                } else if phase == .idle && userScrolling {
                    following = nearEnd(context.geometry)
                    userScrolling = false
                    if following { proxy.scrollTo(endID, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !following {
                    Button("Latest", systemImage: "arrow.down") {
                        following = true
                        proxy.scrollTo(endID, anchor: .bottom)
                    }.font(.caption.weight(.semibold)).buttonStyle(.bordered)
                        .accessibilityLabel("Jump to latest transcript")
                        .padding(.vertical, 4).frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
            }
        }
        .sheet(item: $reviewing) { segment in
            MobileSpeechCorrectionReview(segment: segment) { id in
                restoreOriginal?(id)
                if var snapshot = readingSnapshot, let index = snapshot.firstIndex(where: { $0.id == id }) {
                    snapshot[index] = snapshot[index].restoringOriginal
                    readingSnapshot = snapshot
                }
            }
        }
    }

    private func nearEnd(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height - geometry.visibleRect.maxY <= 32
    }
}

/// Tapping a line with saved audio plays from its time (issue #55). Lines without audio are unchanged.
private struct MobilePlayOnTap: ViewModifier {
    let target: SavedAudioSeek.Target?
    let play: ((SavedAudioSeek.Target) -> Void)?

    func body(content: Content) -> some View {
        if let target, let play {
            content.contentShape(Rectangle()).onTapGesture { play(target) }
                .accessibilityAction(named: "Play from here") { play(target) }
        } else {
            content
        }
    }
}
