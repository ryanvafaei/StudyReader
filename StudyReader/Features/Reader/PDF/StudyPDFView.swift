import AppKit
import PDFKit

/// The `PDFView` of a reader tab. It adds the hooks T59 (highlight clicks, auto-highlight, 1–5 / H keys) needs and
/// nothing else. PDFKit objects stay on the main actor.
///
/// `drawPagePost` is deliberately not overridden: PDFKit calls it from its tiling queue, and an override on a
/// main-actor subclass traps with an executor assertion.
@MainActor
final class StudyPDFView: PDFView {
    /// Called after mouseUp when the selection is non-empty (T59 uses it).
    var onSelectionFinished: (@MainActor (PDFSelection) -> Void)?
    /// Called for a click that doesn't start a selection; return true if handled (T59 hit-tests highlights).
    var onClick: (@MainActor (NSEvent) -> Bool)?
    /// Key handling hook for 1–5 / H (T59); return true if handled.
    var onKeyDown: (@MainActor (NSEvent) -> Bool)?

    private static let clickTolerance: CGFloat = 3
    private var mouseDownPoint: CGPoint?
    private var mouseDidDrag = false

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        mouseDidDrag = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseDidDrag = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let down = mouseDownPoint
        let dragged = mouseDidDrag
        mouseDownPoint = nil
        mouseDidDrag = false

        if let selection = currentSelection, selection.string?.isEmpty == false {
            onSelectionFinished?(selection)
            return
        }
        guard event.clickCount == 1, !dragged, let down else { return }
        let up = convert(event.locationInWindow, from: nil)
        guard hypot(up.x - down.x, up.y - down.y) <= Self.clickTolerance else { return }
        _ = onClick?(event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}
