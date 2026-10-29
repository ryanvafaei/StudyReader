import AppKit
import SwiftUI

/// Read-only selectable text for the Mastery editor (ADR-0021). The selection is `NSTextView`'s own UTF-16
/// `NSRange`, so offsets match `ClozeText`. The ranges of the selected cloze card are tinted.
struct ClozeSelectionTextView: NSViewRepresentable {
    let text: String
    let tintedRanges: [ClozeRange]
    @Binding var selection: ClozeRange?

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(String(localized: "Highlight text"))
        textView.setAccessibilityIdentifier("mastery-text")
        textView.string = text
        applyTint(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.selection = $selection
        if textView.string != text {
            textView.string = text
        }
        applyTint(to: textView)
    }

    private func applyTint(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: full)
        for range in tintedRanges where range.location >= 0 && range.length > 0 && range.location + range.length <= full.length {
            storage.addAttribute(
                .backgroundColor,
                value: NSColor.controlAccentColor.withAlphaComponent(0.35),
                range: NSRange(location: range.location, length: range.length)
            )
        }
        storage.endEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var selection: Binding<ClozeRange?>

        init(selection: Binding<ClozeRange?>) {
            self.selection = selection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let value = range.length > 0 ? ClozeRange(location: range.location, length: range.length) : nil
            if selection.wrappedValue != value {
                selection.wrappedValue = value
            }
        }
    }
}
