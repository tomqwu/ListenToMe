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
struct MobileSelectionSummarySheet: View {
    let session: MobileSession
    let selected: [TranscriptSegment]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var added = false
    private var run: MobileSelectionRun { session.selectionRun }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(span).font(.subheadline.weight(.medium)).foregroundStyle(MobileStyle.muted)
                        .accessibilityIdentifier("selectionSpan")
                    Label(session.selectionSummaryDestination,
                          systemImage: session.ai.provider == .apple ? "iphone" : "network")
                        .font(.caption).foregroundStyle(MobileStyle.muted)
                        .accessibilityIdentifier("selectionSummaryDestination")
                    if let notice = run.notice {
                        Label(notice, systemImage: "scissors").font(.caption).foregroundStyle(MobileStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("selectionSummaryNotice")
                    }
                    if run.isRunning {
                        Label("Summarizing…", systemImage: "sparkles").font(.caption).foregroundStyle(MobileStyle.accent)
                    }
                    if !run.text.isEmpty {
                        MarkdownText(text: run.text).font(.body).lineSpacing(3).textSelection(.enabled)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("selectionSummaryText")
                    }
                    if let error = run.error {
                        Label(error, systemImage: "exclamationmark.circle").font(.callout)
                            .accessibilityIdentifier("selectionSummaryError")
                    }
                    if let result = run.result { actions(result) }
                    Text("AI output can be wrong. Check it against the transcript.")
                        .font(.caption2).foregroundStyle(MobileStyle.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle("Selection summary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if run.isRunning { Button("Cancel") { run.cancel() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeSelectionSummary")
                }
            }
        }
        .onAppear { session.requestSelectionSummary(selected) }
        .onDisappear { if run.isRunning { run.cancel() } }
    }

    private var span: String {
        guard let first = selected.first, let last = selected.last else { return "" }
        return SelectionSummary(start: first.start, end: last.end, lineCount: selected.count,
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
