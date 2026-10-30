import AppKit
import SwiftUI

/// Keep selection, Copy and editing on the same native event path. SwiftUI's selectable Text
/// consumes clicks before its enclosing row's double-tap gesture in the transcript scroll view.
struct NativeTranscriptText: NSViewRepresentable {
    let text: String
    let canEdit: Bool
    let edit: () -> Void

    func makeNSView(context: Context) -> TranscriptTextView {
        let view = TranscriptTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        // SwiftUI owns the frame; the displayed container follows that accepted frame only.
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: TranscriptTextView, context: Context) {
        // A model/status refresh must not discard a user's active text selection.
        if view.string != text { view.string = text }
        view.font = .systemFont(ofSize: 12.5)
        view.textColor = NSColor(Theme.ink)
        view.canEditLine = canEdit
        view.editLine = edit
        view.toolTip = canEdit ? "Double-click to edit this line" : nil
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: TranscriptTextView, context: Context
    ) -> CGSize? {
        let proposed = proposal.width ?? 400
        let width = proposed.isFinite ? max(1, proposed) : 400
        // SwiftUI also probes zero, infinite and unspecified widths. Measuring against the live
        // container would leave its final probe width behind and clip the accepted frame on resize.
        let storage = NSTextStorage(attributedString: nsView.attributedString())
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(16, ceil(layout.usedRect(for: container).height)))
    }
}

final class TranscriptTextView: NSTextView {
    var canEditLine = false
    var editLine: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, canEditLine {
            editLine?()
            return
        }
        super.mouseDown(with: event)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard canEditLine else { return super.accessibilityCustomActions() }
        return (super.accessibilityCustomActions() ?? []) + [
            NSAccessibilityCustomAction(name: "Edit line", handler: { [weak self] in
                guard let self, self.canEditLine, let edit = self.editLine else { return false }
                edit()
                return true
            })
        ]
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if canEditLine {
            menu.addItem(.separator())
            let edit = NSMenuItem(title: "Edit line…", action: #selector(editFromMenu), keyEquivalent: "")
            edit.target = self
            menu.addItem(edit)
        }
        return menu
    }

    @objc private func editFromMenu() {
        guard canEditLine else { return }
        editLine?()
    }
}
