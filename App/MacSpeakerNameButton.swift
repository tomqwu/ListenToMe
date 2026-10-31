import AppKit
import SwiftUI

/// A label that distinguishes deliberate rename from ordinary transcript selection.
final class MacSpeakerNameButton: NSButton {
    var rename: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        if isEnabled, event.clickCount == 2 { rename() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        rename()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if isEnabled, event.characters == " " || event.characters == "\r" { rename() } else {
            super.keyDown(with: event)
        }
    }
}

struct MacSpeakerRenameLabel: NSViewRepresentable {
    let text: String
    let rename: () -> Void

    func makeNSView(context: Context) -> MacSpeakerNameButton {
        let button = MacSpeakerNameButton(frame: .zero)
        button.isBordered = false
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.alignment = .left
        button.font = .systemFont(ofSize: 11, weight: .bold)
        button.contentTintColor = .controlAccentColor
        return button
    }

    func updateNSView(_ button: MacSpeakerNameButton, context: Context) {
        button.title = text
        button.toolTip = "\(text) — Double-click to rename this speaker"
        button.rename = rename
        button.setAccessibilityLabel("Rename speaker \(text)")
    }
}
