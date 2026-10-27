import AppKit
import Foundation

/// Owns the scroll view and the `TextReaderView` of one text reader tab: loads an attributed string, centers the
/// content column, restores and reports the reading position (SPEC F-04) and registers the engine actions on the
/// `ReaderModel`. Knows nothing about Markdown, so the PDF text view can reuse it (ADR-0005).
///
/// An `NSObject` with selector-based observers on purpose: a closure-based observer would send the non-Sendable
/// `Notification` across isolation (same reason as `PDFReaderController`).
@MainActor
final class TextReaderController: NSObject {
    /// F-05 "Medium"; appearance settings come in Phase 3.
    static let contentWidth: CGFloat = 720
    static let minimumHorizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 32
    private static let layoutRetryLimit = 40
    private static let restoreRetryLimit = 5
    private static let layoutRetryDelay: DispatchTimeInterval = .milliseconds(50)

    let scrollView: NSScrollView
    let textView: TextReaderView

    private let model: ReaderModel
    private let decorationDelegate = TextBlockDecorationDelegate()
    /// True once the saved position has been restored (or there was none) and scrolling is reported.
    private(set) var isTrackingPosition = false
    private var lastReportedOffset: Int?
    /// Called each time `load` finishes restoring the position; the highlight code applies a pending location then.
    var onPositionReady: (@MainActor () -> Void)?

    init(model: ReaderModel) {
        self.model = model
        let textView = TextReaderView()
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: Self.minimumHorizontalInset, height: Self.verticalInset)
        scrollView.documentView = textView
        self.scrollView = scrollView
        self.textView = textView
        super.init()

        textView.textLayoutManager?.delegate = decorationDelegate
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(scrollViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    // MARK: - Loading

    /// Shows `attributedString`, registers the engine actions, restores `model.initialTextOffset` once the view has a
    /// layout, and then starts reporting the position.
    func load(_ attributedString: NSAttributedString) {
        isTrackingPosition = false
        textView.textStorage?.setAttributedString(attributedString)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateColumnInset()
        registerActions()

        let saved = model.initialTextOffset
        lastReportedOffset = saved
        performAfterLayout(attempts: Self.layoutRetryLimit) { [weak self] in
            guard let self else { return }
            if let saved {
                restore(toOffset: saved, attemptsLeft: Self.restoreRetryLimit)
            } else {
                beginTrackingPosition()
            }
        }
    }

    /// Applies the saved offset, and re-applies it (up to `restoreRetryLimit` times, 50 ms apart) while the top line
    /// isn't the intended one, because TextKit 2 may still change heights after the first layout. Reporting starts
    /// afterwards: scroll events before that point must not overwrite the saved position.
    private func restore(toOffset offset: Int, attemptsLeft: Int) {
        let lineStart = scrollToLine(containing: offset)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.layoutRetryDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if attemptsLeft > 0, lineStart != nil, self.firstVisibleOffset() != lineStart {
                    self.restore(toOffset: offset, attemptsLeft: attemptsLeft - 1)
                } else {
                    self.beginTrackingPosition()
                }
            }
        }
    }

    private func beginTrackingPosition() {
        isTrackingPosition = true
        onPositionReady?()
    }

    private func registerActions() {
        model.engineActions.findInDocument = { [weak self] in self?.showFindInterface() }
        model.engineActions.copySelection = { [weak self] in self?.textView.copy(nil) }
    }

    private func showFindInterface() {
        textView.window?.makeFirstResponder(textView)
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(sender)
    }

    var textLength: Int { textView.textStorage?.length ?? 0 }

    // MARK: - Content column

    /// Horizontal inset that centers a `contentWidth` column in a view `viewWidth` wide.
    static func columnInset(forViewWidth viewWidth: CGFloat) -> CGFloat {
        max(minimumHorizontalInset, (viewWidth - contentWidth) / 2)
    }

    func updateColumnInset() {
        let inset = Self.columnInset(forViewWidth: scrollView.bounds.width)
        if textView.textContainerInset.width != inset {
            textView.textContainerInset = NSSize(width: inset, height: Self.verticalInset)
        }
        let width = scrollView.contentSize.width
        if width > 0, textView.frame.width != width {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
    }

    // MARK: - Scroll position

    /// UTF-16 offset of the first character of the line at the top of the visible area.
    func firstVisibleOffset() -> Int {
        guard textLength > 0,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return 0 }
        let top = scrollView.contentView.bounds.minY - textView.textContainerOrigin.y
        for step in [0, 4, 8, 16, 32, 64] as [CGFloat] {
            let y = max(top, 0) + 1 + step
            guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 1, y: y)) else { continue }
            let localY = y - fragment.layoutFragmentFrame.minY
            let lines = fragment.textLineFragments
            guard let line = lines.first(where: { $0.typographicBounds.maxY > localY }) ?? lines.last else { continue }
            return Self.offset(of: fragment, in: contentManager) + line.characterRange.location
        }
        return 0
    }

    /// Scrolls so the line containing `offset` is at the top of the visible area (as far as the document allows).
    func scroll(toOffset offset: Int) {
        scrollToLine(containing: offset)
    }

    /// Does the scrolling for `scroll(toOffset:)`. Returns the UTF-16 offset of the first character of that line, or nil
    /// when there is no text.
    @discardableResult
    private func scrollToLine(containing offset: Int) -> Int? {
        guard textLength > 0,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return nil }
        let clamped = min(max(offset, 0), textLength - 1)
        let start = contentManager.documentRange.location
        guard let location = contentManager.location(start, offsetBy: clamped) else { return nil }
        let end = contentManager.location(location, offsetBy: 1) ?? location
        guard let laidOut = NSTextRange(location: start, end: end) else { return nil }
        // Everything above the target gets its real height, so the position doesn't drift while the view scrolls.
        layoutManager.ensureLayout(for: laidOut)
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let fragmentStart = Self.offset(of: fragment, in: contentManager)
        let local = clamped - fragmentStart
        let lines = fragment.textLineFragments
        let line = lines.last(where: { $0.characterRange.location <= local }) ?? lines.first
        let lineTop = fragment.layoutFragmentFrame.minY + (line?.typographicBounds.minY ?? 0)
        scroll(toY: lineTop + textView.textContainerOrigin.y, usageBounds: layoutManager.usageBoundsForTextContainer)
        return fragmentStart + (line?.characterRange.location ?? 0)
    }

    private func scroll(toY y: CGFloat, usageBounds: CGRect) {
        // TextKit 2 grows the view lazily; make sure it is tall enough for the scroll position to be allowed.
        let neededHeight = usageBounds.maxY + 2 * Self.verticalInset
        if textView.frame.height < neededHeight {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: neededHeight))
        }
        let clipView = scrollView.contentView
        let proposed = NSRect(origin: NSPoint(x: clipView.bounds.minX, y: y), size: clipView.bounds.size)
        clipView.scroll(to: clipView.constrainBoundsRect(proposed).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private static func offset(of fragment: NSTextLayoutFragment, in contentManager: NSTextContentManager) -> Int {
        contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
    }

    // MARK: - Selection and anchors

    func select(_ range: NSRange) {
        let length = textLength
        let location = min(max(range.location, 0), length)
        let clamped = NSRange(location: location, length: min(max(range.length, 0), length - location))
        textView.setSelectedRange(clamped)
        textView.scrollRangeToVisible(clamped)
    }

    /// Selects the first match of `term` at or after `offset` (UTF-16, wrapping to the start of the text) and scrolls
    /// to it. Case and diacritics are ignored, and whitespace in the term also matches a line break. False when there
    /// is no match; the view is left alone then. The term is used as a plain string.
    @discardableResult
    func selectFirstMatch(of term: String, from offset: Int) -> Bool {
        guard let range = PlainTextFinder.firstRange(of: term, in: textView.string as NSString, from: offset) else {
            return false
        }
        textView.setSelectedRange(range)
        scroll(toOffset: range.location)
        return true
    }

    /// `range` as a text range of the layout manager, or nil when it lies outside the text.
    func textRange(for range: NSRange) -> NSTextRange? {
        guard let contentManager = textView.textLayoutManager?.textContentManager,
              range.location >= 0, range.length >= 0, NSMaxRange(range) <= textLength,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Rect of `range` in the scroll view's coordinate space, top-left origin (popover anchors, ADR-0017). `.zero`
    /// for a range outside the text.
    func anchorRect(for range: NSRange) -> CGRect {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              range.location >= 0, NSMaxRange(range) <= textLength,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return .zero }
        layoutManager.ensureLayout(for: textRange)
        var union = CGRect.null
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.union(frame)
            return true
        }
        guard !union.isNull else { return .zero }
        let origin = textView.textContainerOrigin
        let inTextView = union.offsetBy(dx: origin.x, dy: origin.y)
        let converted = scrollView.convert(inTextView, from: textView)
        if scrollView.isFlipped {
            return converted
        }
        return CGRect(
            x: converted.minX,
            y: scrollView.bounds.height - converted.maxY,
            width: converted.width,
            height: converted.height
        )
    }

    // MARK: - Position reporting

    private func reportPositionIfNeeded() {
        guard isTrackingPosition else { return }
        let offset = firstVisibleOffset()
        guard offset != lastReportedOffset else { return }
        lastReportedOffset = offset
        model.textPositionChanged(offset: offset, textLength: textLength)
    }

    @objc private func scrollViewFrameDidChange(_ notification: Notification) {
        updateColumnInset()
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        reportPositionIfNeeded()
    }

    /// Runs `work` when the view is in a window with a size, or after `attempts` retries (50 ms apart) regardless.
    /// The first try is on the next run loop turn.
    private func performAfterLayout(
        attempts: Int,
        delay: DispatchTimeInterval = .milliseconds(0),
        _ work: @escaping @MainActor () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let size = self.scrollView.bounds.size
                let isLaidOut = self.scrollView.window != nil && size.width > 0 && size.height > 0
                if isLaidOut || attempts <= 0 {
                    self.textView.layoutSubtreeIfNeeded()
                    work()
                } else {
                    self.performAfterLayout(attempts: attempts - 1, delay: Self.layoutRetryDelay, work)
                }
            }
        }
    }
}
