import AppKit
import PDFKit

/// The drag surface of snapshot mode (SPEC F-08). It covers the PDF view, shows a crosshair, draws a translucent
/// rectangle that follows the drag and reports the finished drag in the PDF view's coordinates. Scrolling still
/// works: wheel events go to the PDF view's own scroll view.
@MainActor
final class SnapshotOverlayView: NSView {
    /// A finished drag: the rect and the point where it started, in the coordinates of the overlay's superview.
    var onFinish: (@MainActor (_ rect: CGRect, _ start: CGPoint) -> Void)?
    var onCancel: (@MainActor () -> Void)?

    private weak var host: StudyPDFView?
    private var startPoint: CGPoint?
    private(set) var dragRect: CGRect?

    init(host: StudyPDFView) {
        self.host = host
        super.init(frame: host.bounds)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        dragRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        dragRect = Self.rect(from: startPoint, to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let rect = Self.rect(from: startPoint, to: convert(event.locationInWindow, from: nil))
        self.startPoint = nil
        dragRect = nil
        needsDisplay = true
        onFinish?(rect, startPoint)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == StudyPDFView.escapeKeyCode {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func scrollWheel(with event: NSEvent) {
        host?.documentView?.enclosingScrollView?.scrollWheel(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let dragRect, dragRect.width > 0 || dragRect.height > 0 else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        dragRect.fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: dragRect)
        outline.lineWidth = 1
        outline.stroke()
    }

    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
