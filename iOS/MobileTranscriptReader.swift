import SwiftUI
import ListenToMeCore

/// Follow new speech until the reader deliberately scrolls away from the end.
struct MobileTranscriptReader: View {
    let segments: [TranscriptSegment]
    var scrollIdentifier = "transcriptScroll"
    var translation: ((TranscriptSegment) -> String?)?
    var translationProblem: ((UUID) -> String?)?
    var restoreOriginal: ((UUID) -> Void)?
    /// Shows who said each line once speaker identification has labeled any of them (issue #180).
    var showsSpeakers = false
    /// Select mode (issue #234): tapping a final line toggles it; dragging its circle extends a range.
    var selection: Binding<TranscriptSelection>?
    var selecting = false
    /// Touch-and-hold actions on a final line (Summarize from here, Select from here); nil hides them.
    var lineActions: MobileTranscriptLineActions?
    @State private var rowFrames: [UUID: CGRect] = [:]
    private static let space = "transcriptRows"
    /// Where a line plays from in the saved audio (issue #55); `nil` hides the play controls.
    var audioTarget: ((TranscriptSegment) -> SavedAudioSeek.Target?)?
    var playAudio: ((SavedAudioSeek.Target) -> Void)?
    /// "Add to My terms" from a line's context menu (issue #222); returns why a term was not added.
    var addTerm: ((String) -> String?)?
    @State private var reviewing: TranscriptSegment?
    @State private var addingFrom: TranscriptSegment?
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
                        row(segment)
                    }
                    Color.clear.frame(height: 1).id(endID)
                }.padding(16).coordinateSpace(.named(Self.space))
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
        .sheet(item: $addingFrom) { segment in
            MobileAddTermSheet(line: segment.text) { addTerm?($0) }
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

    // MARK: Rows and Select mode (issue #234)

    @ViewBuilder
    private func row(_ segment: TranscriptSegment) -> some View {
        if selecting, segment.isFinal, let selection {
            let chosen = selection.wrappedValue.ids.contains(segment.id)
            Button { selection.wrappedValue.toggle(segment.id, in: segments) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(chosen ? MobileStyle.accent : MobileStyle.muted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                        // Dragging down (or up) the circles extends the range from where it started.
                        .highPriorityGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
                            .onChanged { value in
                                if let target = rowFrames.first(where: { $0.value.contains(value.location) })?.key {
                                    selection.wrappedValue.extend(from: segment.id, to: target, in: segments)
                                }
                            })
                        .accessibilityHidden(true)
                    lineContent(segment, selectable: false)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { rowFrames[segment.id] = $0 }
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityIdentifier("select-line-\(segment.id)")
        } else {
            lineContent(segment, selectable: !selecting)
                .modifier(MobilePlayOnTap(target: audioTarget?(segment), play: playAudio))
                .contextMenu { if segment.isFinal, !selecting { lineMenu(segment) } }
        }
    }

    /// A final line's touch-and-hold menu. Summarize from here is disabled, with the reason under it,
    /// when no provider can run.
    @ViewBuilder
    private func lineMenu(_ segment: TranscriptSegment) -> some View {
        if let text = translation?(segment) {
            Button("Copy translation", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
        if let lineActions {
            let reason = lineActions.summarizeBlockReason
            Button { lineActions.summarizeFrom(segment.id) } label: {
                Label("Summarize from here", systemImage: "text.badge.star")
                if let reason { Text(reason) }
            }.disabled(reason != nil)
            Button("Select from here", systemImage: "checklist") { lineActions.selectFrom(segment.id) }
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = segment.text }
        }
        if addTerm != nil {
            Button("Add to My terms…", systemImage: "text.badge.plus") { addingFrom = segment }
                .accessibilityIdentifier("addToMyTerms")
        }
    }

    private func lineContent(_ segment: TranscriptSegment, selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !segment.isFinal {
                Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(MobileStyle.transcript)
            }
            if !selecting, let target = audioTarget?(segment) {
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
            lineText(segment, selectable: selectable)
            if let text = translation?(segment) {
                TranslatedTranscriptText(text: text).accessibilityIdentifier("translated-line-\(segment.id)")
            } else if let problem = translationProblem?(segment.id) {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
            if segment.originalText != nil, restoreOriginal != nil, !selecting {
                Button("AI corrected", systemImage: "sparkles") { reviewing = segment }
                    .font(.caption).buttonStyle(.borderless)
                    .accessibilityIdentifier("review-correction-\(segment.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Text stays selectable alongside the line's menu, as before #234; only Select mode, where a tap
    /// toggles the whole line, turns it off.
    @ViewBuilder
    private func lineText(_ segment: TranscriptSegment, selectable: Bool) -> some View {
        let text = Text(segment.text).font(.body).lineSpacing(4)
            .foregroundStyle(segment.isFinal ? .primary : .secondary)
            .accessibilityIdentifier("transcript-text-\(segment.id)")
            .accessibilityActions {
                // The touch-and-hold menu's actions, for VoiceOver's actions rotor, on the line's text.
                if let lineActions, segment.isFinal, !selecting {
                    Button("Summarize from here") { lineActions.summarizeFrom(segment.id) }
                        .disabled(lineActions.summarizeBlockReason != nil)
                    Button("Select from here") { lineActions.selectFrom(segment.id) }
                }
            }
        if selectable { text.textSelection(.enabled) } else { text }
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
