//
//  InlineTextField.swift
//  PDFHandler
//
//  The editor a text placement swaps in while it is being edited.
//
//  This is plain AppKit on purpose. The SwiftUI TextField it replaces
//  was focused with a single deferred @FocusState request; when that
//  request was dropped (it happens intermittently once a few fields
//  have come and gone) the box sat in edit mode with nothing focused,
//  so keystrokes went nowhere. Under Dark Mode that stuck state was
//  also invisible: the placeholder and caret took the dark scheme's
//  light colors and vanished against the white page. Here the field
//  makes itself first responder when it lands in a window, which AppKit
//  honors deterministically, and is pinned to the light appearance
//  because it always sits on paper.
//

import SwiftUI
import AppKit

struct InlineTextField: NSViewRepresentable {
    /// Text at the start of the edit session. Only read on creation:
    /// pushing it back in on every keystroke would move the caret.
    let initialText: String
    let placeholder: String
    let font: NSFont
    /// While true the field ignores the mouse, so an ⌥-drag reaches
    /// the placement's move gesture instead of selecting text.
    let passesMouseThrough: Bool
    let onChange: (String) -> Void
    /// Return, Esc, Tab, or focus moving elsewhere. May be called more
    /// than once per session by AppKit; the Coordinator coalesces it.
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField(string: initialText)
        field.appearance = NSAppearance(named: .aqua)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .black
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = font
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.gray.withAlphaComponent(0.65),
                .font: font,
            ]
        )
        field.delegate = context.coordinator
        field.passesMouseThrough = passesMouseThrough
        // Fill whatever width the box offers rather than growing with
        // the text; long text scrolls inside the box instead.
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.parent = self
        field.passesMouseThrough = passesMouseThrough
        if field.font != font {
            // Zoom or an inspector style change mid-edit.
            field.font = font
            (field.currentEditor() as? NSTextView)?.font = font
            if let placeholder = field.placeholderAttributedString {
                let updated = NSMutableAttributedString(attributedString: placeholder)
                updated.addAttribute(.font, value: font, range: NSRange(location: 0, length: updated.length))
                field.placeholderAttributedString = updated
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusingTextField, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width ?? (intrinsic.width > 0 ? intrinsic.width : 1)
        return CGSize(width: width, height: intrinsic.height)
    }

    static func dismantleNSView(_ field: FocusingTextField, coordinator: Coordinator) {
        // Teardown can make AppKit report "end editing"; the session is
        // already over by then, so don't report it a second time.
        coordinator.finished = true
        field.delegate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTextField
        var finished = false

        init(_ parent: InlineTextField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard !finished, let field = note.object as? NSTextField else { return }
            parent.onChange(field.stringValue)
        }

        func controlTextDidEndEditing(_ note: Notification) {
            finish()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.cancelOperation(_:)),
                 #selector(NSResponder.insertTab(_:)),
                 #selector(NSResponder.insertBacktab(_:)):
                // Drop focus explicitly so the field editor doesn't
                // linger as first responder once the field is gone.
                control.window?.makeFirstResponder(nil)
                finish()
                return true
            default:
                return false
            }
        }

        private func finish() {
            guard !finished else { return }
            finished = true
            parent.onEnd()
        }
    }
}

/// An NSTextField that takes keyboard focus as soon as it is placed in
/// a window. Deferred one turn so SwiftUI has finished the update that
/// inserted it before the responder chain changes.
final class FocusingTextField: NSTextField {
    var passesMouseThrough = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Checked live as well as via the flag: the click that starts
        // an ⌥-drag can arrive before SwiftUI has pushed the update.
        if passesMouseThrough || NSEvent.modifierFlags.contains(.option) { return nil }
        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.currentEditor() == nil else { return }
            window.makeFirstResponder(self)
        }
    }
}
