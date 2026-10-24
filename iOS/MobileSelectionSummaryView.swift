import SwiftUI
import ListenToMeCore
import UIKit

/// The bar under the transcript while selecting (issue #234): how many lines are picked, where a
/// summary would be sent, and Summarize selection — disabled with the reason when it cannot run.
struct MobileSelectionBar: View {
    let session: MobileSession
    let selected: [TranscriptSegment]
    let summarize: () -> Void
    let done: () -> Void

    var body: some View {
        let reason = session.selectionSummaryBlockReason(selected)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selected.count == 1 ? "1 line selected" : "\(selected.count) lines selected")
                    .font(.caption.weight(.semibold)).accessibilityIdentifier("selectionCount")
                Spacer()
                Button("Done", action: done).font(.caption.weight(.semibold))
                    .accessibilityIdentifier("endSelection")
            }
            Button(action: summarize) {
                Label("Summarize selection", systemImage: "text.badge.star").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.small).tint(MobileStyle.accent)
            .disabled(reason != nil).accessibilityIdentifier("summarizeSelection")
            Text(reason ?? session.selectionSummaryDestination)
                .font(.caption2).foregroundStyle(MobileStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(reason == nil ? "selectionDestination" : "selectionBlockReason")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain).accessibilityIdentifier("selectionBar")
    }
}

/// The selection summary: bullets of only the chosen lines, with Copy, Share and Add to notes.
///
/// It shows nothing from an earlier request: opening it prepares a clean run keyed to this request
/// and this conversation. On Apple Intelligence it starts at once; with any other provider it first
/// says where the lines go and sends them only when the user taps Summarize.
struct MobileSelectionSummarySheet: View {
    let session: MobileSession
    let request: MobileSelectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var added = false
    private var run: MobileSelectionRun { session.selectionRun }
    /// The run state, only while it belongs to this request in the open conversation.
    private var current: Bool { run.matches(request.id, conversation: session.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(span).font(.subheadline.weight(.medium)).foregroundStyle(MobileStyle.muted)
                        .accessibilityIdentifier("selectionSpan")
                    Label(session.selectionSummaryDestination,
                          systemImage: session.selectionSummaryStaysOnDevice ? "iphone" : "network")
                        .font(.caption).foregroundStyle(MobileStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("selectionSummaryDestination")
                    if current { state }
                    Text("AI output can be wrong. Check it against the transcript.")
                        .font(.caption2).foregroundStyle(MobileStyle.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle("Selection summary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if current && run.isRunning {
                        Button("Cancel") { session.cancelSelectionSummary() }
                            .accessibilityIdentifier("cancelSelectionSummary")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeSelectionSummary")
                }
            }
        }
        .onAppear { session.prepareSelectionSummary(request) }
        .onDisappear { if current && run.isRunning { session.cancelSelectionSummary() } }
    }

    @ViewBuilder
    private var state: some View {
        switch run.phase {
        case .ready:
            Button { session.startSelectionSummary(request) } label: {
                Label("Summarize", systemImage: "paperplane").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(MobileStyle.accent)
            .accessibilityHint(session.selectionSummaryDestination)
            .accessibilityIdentifier("startSelectionSummary")
        case .running:
            Label("Summarizing…", systemImage: "sparkles").font(.caption).foregroundStyle(MobileStyle.accent)
            answer
        case .finished:
            notice
            answer
            if let result = run.result { actions(result) }
        case .blocked:
            Label(run.message ?? "", systemImage: "info.circle").font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("selectionSummaryBlocked")
        case .failed:
            notice
            Label(run.message ?? "", systemImage: "exclamationmark.circle").font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("selectionSummaryError")
        case .cancelled:
            Text(run.message ?? "Cancelled.").font(.callout).foregroundStyle(MobileStyle.muted)
                .accessibilityIdentifier("selectionSummaryCancelled")
            Button("Summarize again", systemImage: "arrow.clockwise") { session.startSelectionSummary(request) }
                .buttonStyle(.bordered).accessibilityIdentifier("restartSelectionSummary")
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = run.notice {
            Label(notice, systemImage: "scissors").font(.caption).foregroundStyle(MobileStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("selectionSummaryNotice")
        }
    }

    @ViewBuilder
    private var answer: some View {
        if !run.text.isEmpty {
            MarkdownText(text: run.text).font(.body).lineSpacing(3).textSelection(.enabled)
                .accessibilityElement(children: .combine).accessibilityIdentifier("selectionSummaryText")
        }
    }

    private var span: String {
        guard let first = request.lines.first, let last = request.lines.last else { return "" }
        return SelectionSummary(start: first.start, end: last.end, lineCount: request.lines.count,
                                shortened: false, text: "").span
    }

    private func actions(_ result: SelectionSummary) -> some View {
        HStack(spacing: 10) {
            Button(copied ? "Copied" : "Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = MobileSession.readableText(result.text); copied = true
            }.accessibilityIdentifier("copySelectionSummary")
            ShareLink(item: MobileSession.readableText(result.text)) { Label("Share", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("shareSelectionSummary")
            Button(added ? "Added" : "Add to notes", systemImage: "note.text.badge.plus") {
                session.addSelectionSummaryToNotes(result); added = true
            }.disabled(added).accessibilityIdentifier("addSelectionSummaryToNotes")
        }.buttonStyle(.bordered).font(.subheadline)
    }
}

/// The conversation's last few selection summaries, under its Summary, collapsed (issue #234).
struct MobileSavedSelectionSummaries: View {
    let summaries: [SelectionSummary]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(summaries) { summary in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.span).font(.caption.weight(.semibold)).foregroundStyle(MobileStyle.muted)
                        MarkdownText(text: summary.text).font(.callout).textSelection(.enabled)
                    }.accessibilityElement(children: .combine)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        } label: {
            Text(summaries.count == 1 ? "1 selection summary" : "\(summaries.count) selection summaries")
                .font(.subheadline.weight(.medium)).foregroundStyle(MobileStyle.ink)
        }
        .padding(12)
        .background(MobileStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("savedSelectionSummaries")
    }
}
