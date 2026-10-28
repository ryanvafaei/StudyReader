import AppKit

/// The read-only, selectable text view shared by the Markdown reader and (Phase 3) the PDF text view (ADR-0005).
/// TextKit 2 only: nothing here or in the controller may touch `layoutManager`, which would switch the view back to
/// TextKit 1.
@MainActor
final class TextReaderView: NSTextView {
    /// Called after a mouse-up that leaves a non-empty selection (T60).
    var onSelectionFinished: (@MainActor (NSRange) -> Void)?
    /// Called for a click that doesn't select and isn't on a link (a link click never gets here, see `didClickLink`):
    /// the character index under the pointer. The Bool result is informational only; nothing runs after it in
    /// `mouseDown` (T60).
    var onClick: (@MainActor (Int, NSEvent) -> Bool)?
    /// Key handling hook for 1-5 / H (T60); return true if handled.
    var onKeyDown: (@MainActor (NSEvent) -> Bool)?

    /// Link schemes that open outside the app; every other link is ignored.
    static let openableLinkSchemes: Set<String> = ["http", "https", "mailto"]
    private static let clickTolerance: CGFloat = 3
    /// Set by `clicked(onLink:at:)` while `super.mouseDown` tracks the click, so a link click isn't also a highlight click.
    private var didClickLink = false

    /// The TextKit 2 objects the view works with. Held here so they live as long as the view.
    private let contentStorage: NSTextContentStorage
    private let layoutManagerStorage: NSTextLayoutManager

    init() {
        let storage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        storage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        contentStorage = storage
        layoutManagerStorage = layoutManager
        super.init(frame: .zero, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        isRichText = true
        allowsUndo = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        unregisterDraggedTypes()
        setAccessibilityLabel(String(localized: "Document text"))
    }

    // MARK: - Hit testing

    /// UTF-16 offset of the character under `point` (view coordinates), or nil when the point isn't on a line of text.
    func characterIndex(at point: CGPoint) -> Int? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return nil }
        let origin = textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) else { return nil }
        let local = CGPoint(
            x: containerPoint.x - fragment.layoutFragmentFrame.minX,
            y: containerPoint.y - fragment.layoutFragmentFrame.minY
        )
        guard let line = fragment.textLineFragments.first(where: { $0.typographicBounds.contains(local) }) else {
            return nil
        }
        let bounds = line.typographicBounds
        let inLine = line.characterIndex(for: CGPoint(x: local.x - bounds.minX, y: local.y - bounds.minY))
        let fragmentStart = contentManager.offset(
            from: contentManager.documentRange.location,
            to: fragment.rangeInElement.location
        )
        let index = fragmentStart + inLine
        return (0..<max(textStorage?.length ?? 0, 0)).contains(index) ? index : nil
    }

    // MARK: - Events

    override func mouseDown(with event: NSEvent) {
        let down = convert(event.locationInWindow, from: nil)
        didClickLink = false
        // NSTextView tracks the whole drag inside `super`, so it returns after the mouse is released.
        super.mouseDown(with: event)
        if didClickLink { return }

        let selection = selectedRange()
        if selection.length > 0 {
            onSelectionFinished?(selection)
            return
        }
        guard event.clickCount == 1, let window else { return }
        let up = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard hypot(up.x - down.x, up.y - down.y) <= Self.clickTolerance,
              let index = characterIndex(at: down) else { return }
        _ = onClick?(index, event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    // MARK: - Highlights

    /// One stored highlight to paint: the UTF-16 range and its (translucent) color.
    struct HighlightPaint: Equatable {
        let range: NSRange
        let color: NSColor
    }

    /// The highlights `TextHighlightController` painted, oldest first (the newest is drawn last, on top). They are
    /// drawn here, under the text, rather than as TextKit 2 rendering attributes, which didn't paint reliably.
    var highlightPaints: [HighlightPaint] = [] {
        didSet { needsDisplay = true }
    }

    /// The paints that can show in `viewport` (UTF-16), each clipped to it, in the same order. All paints unchanged
    /// when `viewport` is nil.
    static func paintsToDraw(_ paints: [HighlightPaint], viewport: NSRange?) -> [HighlightPaint] {
        guard let viewport else { return paints }
        return paints.compactMap { paint in
            let clipped = NSIntersectionRange(paint.range, viewport)
            guard clipped.length > 0 else { return nil }
            return HighlightPaint(range: clipped, color: paint.color)
        }
    }

    /// The laid-out viewport as a UTF-16 range, or nil when TextKit has none yet (or it is empty).
    private func viewportRange() -> NSRange? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return nil }
        let documentStart = contentManager.documentRange.location
        let location = contentManager.offset(from: documentStart, to: viewport.location)
        let length = contentManager.offset(from: viewport.location, to: viewport.endLocation)
        return length > 0 ? NSRange(location: location, length: length) : nil
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard !highlightPaints.isEmpty, let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }
        let origin = textContainerOrigin
        let length = textStorage?.length ?? 0
        for paint in Self.paintsToDraw(highlightPaints, viewport: viewportRange()) {
            guard paint.range.location >= 0, paint.range.length > 0, NSMaxRange(paint.range) <= length,
                  let start = contentManager.location(contentManager.documentRange.location, offsetBy: paint.range.location),
                  let end = contentManager.location(start, offsetBy: paint.range.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            layoutManager.ensureLayout(for: textRange)
            paint.color.setFill()
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                let segment = frame.offsetBy(dx: origin.x, dy: origin.y)
                if segment.width > 0, segment.intersects(rect) {
                    segment.fill(using: .sourceOver)
                }
                return true
            }
        }
    }

    // MARK: - Links

    /// Opens `http`, `https` and `mailto` links in the default app; ignores every other scheme.
    override func clicked(onLink link: Any, at charIndex: Int) {
        didClickLink = true
        guard let url = Self.url(forLink: link), Self.isOpenable(url) else { return }
        NSWorkspace.shared.open(url)
    }

    static func url(forLink link: Any) -> URL? {
        if let url = link as? URL { return url }
        if let string = link as? String { return URL(string: string) }
        return nil
    }

    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return openableLinkSchemes.contains(scheme)
    }
}
