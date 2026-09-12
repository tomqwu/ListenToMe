import SwiftUI
import ListenToMeCore

/// Follow new speech until the reader deliberately scrolls away from the end.
struct MobileTranscriptReader: View {
    let segments: [TranscriptSegment]
    var scrollIdentifier = "transcriptScroll"
    @State private var following = true
    @State private var userScrolling = false
    private let endID = "transcript-end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if segments.isEmpty {
                        Text("Start listening and your words will appear here.").foregroundStyle(.secondary)
                    }
                    ForEach(segments) { segment in
                        VStack(alignment: .leading, spacing: 5) {
                            if !segment.isFinal {
                                Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(.indigo)
                            }
                            Text(segment.text).font(.body).lineSpacing(4).textSelection(.enabled)
                                .foregroundStyle(segment.isFinal ? .primary : .secondary)
                                .accessibilityIdentifier("transcript-text-\(segment.id)")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(endID)
                }.padding(16)
            }
            .accessibilityIdentifier(scrollIdentifier)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onChange(of: segments.last) { _, _ in
                if following && !userScrolling { proxy.scrollTo(endID, anchor: .bottom) }
            }
            // Also follow wrapping partial text after layout, not only newly finalized segment IDs.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
                if following && !userScrolling { proxy.scrollTo(endID, anchor: .bottom) }
            }
            .onScrollGeometryChange(for: Bool.self) { nearEnd($0) } action: { _, atEnd in
                if userScrolling { following = atEnd }
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
    }

    private func nearEnd(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height - geometry.visibleRect.maxY <= 32
    }
}
