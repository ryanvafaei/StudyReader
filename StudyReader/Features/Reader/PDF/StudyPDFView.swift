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

    /// Called when the effective appearance (light or dark) changes; the controller re-evaluates the dark-mode inversion.
    var onEffectiveAppearanceChange: (@MainActor () -> Void)?

    /// Called when a snapshot drag ends: the rect and its start point in this view's coordinates (T61).
    var onSnapshotDrag: (@MainActor (_ rect: CGRect, _ start: CGPoint) -> Void)?
    /// Called when snapshot mode ends without a capture (Escape).
    var onSnapshotCancel: (@MainActor () -> Void)?

    /// Called when the view moves into a window (the controller starts position tracking if it was waiting for one).
    var onWindowAttached: (@MainActor () -> Void)?

    static let escapeKeyCode: UInt16 = 53
    private static let clickTolerance: CGFloat = 3
    private var snapshotOverlay: SnapshotOverlayView?
    private var mouseDownPoint: CGPoint?
    private var mouseDidDrag = false

    /// True while the snapshot drag overlay is on top of the document.
    var isSnapshotModeActive: Bool { snapshotOverlay != nil }

    /// Puts the crosshair overlay over the document and takes keyboard focus so Escape reaches it.
    func beginSnapshotMode() {
        guard snapshotOverlay == nil else { return }
        let overlay = SnapshotOverlayView(host: self)
        overlay.onFinish = { [weak self] rect, start in self?.onSnapshotDrag?(rect, start) }
        overlay.onCancel = { [weak self] in self?.onSnapshotCancel?() }
        addSubview(overlay)
        snapshotOverlay = overlay
        window?.makeFirstResponder(overlay)
        window?.invalidateCursorRects(for: overlay)
    }

    func endSnapshotMode() {
        guard let overlay = snapshotOverlay else { return }
        snapshotOverlay = nil
        overlay.removeFromSuperview()
        if window?.firstResponder === overlay {
            window?.makeFirstResponder(self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onWindowAttached?()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }

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
        if isSnapshotModeActive, event.keyCode == Self.escapeKeyCode {
            onSnapshotCancel?()
            return
        }
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}
