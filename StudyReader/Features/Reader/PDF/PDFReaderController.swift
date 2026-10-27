import AppKit
import Foundation
import Observation
import PDFKit

/// Owns the PDF view of one reader tab: display settings, zoom, navigation, outline, and the reading position
/// (SPEC F-04). It registers the engine actions on the `ReaderModel` and reports position changes to it. PDFKit
/// objects never leave the main actor, and the document is never written (ADR-0003).
///
/// An `NSObject` with selector-based observers on purpose: a closure-based observer would send the non-Sendable
/// `Notification` across isolation (same reason as `ReaderWindowObserver`).
@MainActor @Observable
final class PDFReaderController: NSObject {
    static let minimumScale: CGFloat = 0.25
    static let maximumScale: CGFloat = 5
    private static let pageBreakMargin: CGFloat = 8
    private static let layoutRetryLimit = 40
    private static let layoutRetryDelay: DispatchTimeInterval = .milliseconds(50)
    /// A change smaller than this (in page-space points) on the same page isn't worth saving.
    private static let positionTolerance = 0.5

    let pdfView: StudyPDFView
    private(set) var document: PDFDocument?
    private(set) var outline: [PDFOutlineItem] = []
    private(set) var pageCount = 0
    /// 0-based page shown in the page field; follows `PDFViewPageChanged`.
    private(set) var displayedPageIndex = 0
    private(set) var isSinglePage = false
    /// True after `load(url:)` ran, whether or not the document opened.
    private(set) var didAttemptLoad = false
    var showsThumbnails = false

    @ObservationIgnored private let model: ReaderModel
    @ObservationIgnored private weak var observedClipView: NSClipView?
    @ObservationIgnored private var isTrackingPosition = false
    @ObservationIgnored private var lastReportedPosition: PDFPosition?
    /// Mirror of `AppSettings.invertPDFInDarkMode`; kept current by `setInversionEnabled(_:)` (PDFInversion.swift).
    @ObservationIgnored var invertSettingEnabled: Bool
    /// Whether the dark-mode filters are on; set by `setInverted(_:)` (PDFInversion.swift).
    @ObservationIgnored var isInverted = false

    init(model: ReaderModel) {
        self.model = model
        self.invertSettingEnabled = model.session.settings.invertPDFInDarkMode
        self.pdfView = StudyPDFView(frame: .zero)
        super.init()
        pdfView.onEffectiveAppearanceChange = { [weak self] in self?.refreshInversion() }
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = NSEdgeInsets(
            top: Self.pageBreakMargin,
            left: Self.pageBreakMargin,
            bottom: Self.pageBreakMargin,
            right: Self.pageBreakMargin
        )
        pdfView.minScaleFactor = Self.minimumScale
        pdfView.maxScaleFactor = Self.maximumScale
        pdfView.autoScales = true
        pdfView.backgroundColor = .windowBackgroundColor
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pageDidChange(_:)), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(self, selector: #selector(scaleDidChange(_:)), name: .PDFViewScaleChanged, object: pdfView)
    }

    // MARK: - Loading

    /// Opens the PDF on the main actor, restores `model.initialPDFPosition` (else the top of page 1), registers the
    /// engine actions on the model and starts position tracking. A file PDFKit can't open (or a locked one) fails the
    /// model and registers nothing.
    func load(url: URL) {
        didAttemptLoad = true
        guard let loaded = PDFDocument(url: url), Self.isReadable(loaded) else {
            model.engineFailed(String(localized: "The document couldn't be opened."))
            return
        }
        document = loaded
        pageCount = loaded.pageCount
        outline = loaded.outlineRoot.map { Self.outlineItems(of: $0, in: loaded) } ?? []
        isTrackingPosition = false
        lastReportedPosition = model.initialPDFPosition
        pdfView.autoScales = true
        pdfView.document = loaded
        refreshInversion()
        registerActions()

        let saved = model.initialPDFPosition
        performAfterLayout(attempts: Self.layoutRetryLimit) { [weak self] in
            guard let self else { return }
            if let saved {
                applyPosition(saved)
            }
            // Layout-induced scroll events before this point must not overwrite the saved position.
            Task { @MainActor [weak self] in
                self?.beginTrackingPosition()
            }
        }
    }

    private static func isReadable(_ document: PDFDocument) -> Bool {
        if document.isLocked {
            _ = document.unlock(withPassword: "")
        }
        return !document.isLocked && document.pageCount > 0
    }

    private func registerActions() {
        model.engineActions.zoomIn = { [weak self] in self?.zoomIn() }
        model.engineActions.zoomOut = { [weak self] in self?.zoomOut() }
        model.engineActions.actualSize = { [weak self] in self?.actualSize() }
        model.engineActions.fitWidth = { [weak self] in self?.fitWidth() }
        model.engineActions.toggleSinglePage = { [weak self] in
            guard let self else { return }
            setSinglePage(!isSinglePage)
        }
        model.engineActions.toggleThumbnails = { [weak self] in self?.showsThumbnails.toggle() }
        model.engineActions.currentPageIndex = { [weak self] in self?.currentPageIndex }
    }

    private func beginTrackingPosition() {
        isTrackingPosition = true
        observeClipView()
        displayedPageIndex = currentPageIndex ?? 0
        applyPendingLocation()
    }

    // MARK: - Zoom and display

    func zoomIn() {
        pdfView.autoScales = false
        pdfView.zoomIn(nil)
    }

    func zoomOut() {
        pdfView.autoScales = false
        pdfView.zoomOut(nil)
    }

    func actualSize() {
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
    }

    func fitWidth() {
        guard let scale = fitWidthScale else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = scale
    }

    /// The scale at which the current page's width fills the visible width, minus the page-break margins.
    var fitWidthScale: CGFloat? {
        guard let page = pdfView.currentPage ?? document?.page(at: 0) else { return nil }
        let crop = page.bounds(for: .cropBox)
        let pageWidth = page.rotation % 180 == 0 ? crop.width : crop.height
        let visibleWidth = Self.scrollView(in: pdfView)?.contentSize.width ?? pdfView.bounds.width
        let margins = pdfView.displaysPageBreaks ? pdfView.pageBreakMargins.left + pdfView.pageBreakMargins.right : 0
        return Self.fitWidthScale(visibleWidth: visibleWidth, margins: margins, pageWidth: pageWidth)
    }

    /// Pure scale math behind Fit Width. Nil for a page without width.
    static func fitWidthScale(visibleWidth: CGFloat, margins: CGFloat, pageWidth: CGFloat) -> CGFloat? {
        guard pageWidth > 0, visibleWidth > margins else { return nil }
        return (visibleWidth - margins) / pageWidth
    }

    /// Switches between single-page and continuous display and keeps the reading spot.
    func setSinglePage(_ singlePage: Bool) {
        let destination = pdfView.currentDestination
        isSinglePage = singlePage
        pdfView.displayMode = singlePage ? .singlePage : .singlePageContinuous
        if let destination {
            pdfView.go(to: destination)
        }
        applyInversionToDocumentView()
        observeClipView()
    }

    // MARK: - Navigation

    func go(toPage index: Int) {
        guard let document, let page = document.page(at: index) else { return }
        pdfView.go(to: page)
    }

    /// Gives keyboard focus back to the document, so the arrow keys scroll after the page field was used.
    func focusDocument() {
        pdfView.window?.makeFirstResponder(pdfView)
    }

    /// Applies a `.page` location the model holds and consumes it. Other locations belong to T59 and T67. Before the
    /// saved position is restored the call does nothing; `beginTrackingPosition` applies it afterwards.
    func applyPendingLocation() {
        guard isTrackingPosition, case .page(let index)? = model.pendingLocation else { return }
        go(toPage: index)
        model.consumeLocation()
        reportPositionIfNeeded()
    }

    var currentPageIndex: Int? {
        guard let document else { return nil }
        guard let page = pdfView.currentPage else { return 0 }
        let index = document.index(for: page)
        return index == NSNotFound ? 0 : index
    }

    // MARK: - Reading position (F-04)

    /// Page index plus the page-space y of the top of the visible area (from `currentDestination`).
    func currentPosition() -> PDFPosition? {
        guard let document, let destination = pdfView.currentDestination, let page = destination.page else { return nil }
        let index = document.index(for: page)
        let y = destination.point.y
        guard index != NSNotFound, y.isFinite else { return nil }
        return PDFPosition(pageIndex: index, offsetY: Double(y))
    }

    /// Scrolls so `position.offsetY` is at the top of the visible area on `position.pageIndex`. Runs once the view
    /// has been laid out (next run loop turn at the earliest).
    func restore(_ position: PDFPosition) {
        performAfterLayout(attempts: Self.layoutRetryLimit) { [weak self] in
            self?.applyPosition(position)
        }
    }

    private func applyPosition(_ position: PDFPosition) {
        guard let document, document.pageCount > 0 else { return }
        let index = min(max(position.pageIndex, 0), document.pageCount - 1)
        guard let page = document.page(at: index) else { return }
        pdfView.layoutDocumentView()
        let origin = page.bounds(for: .cropBox).minX
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: origin, y: position.offsetY)))
    }

    private func reportPositionIfNeeded() {
        guard isTrackingPosition, let position = currentPosition() else { return }
        if let last = lastReportedPosition,
           last.pageIndex == position.pageIndex,
           abs(last.offsetY - position.offsetY) < Self.positionTolerance {
            return
        }
        lastReportedPosition = position
        model.pdfPositionChanged(position, pageCount: pageCount)
    }

    /// Scroll events come from the clip view of PDFKit's internal scroll view, which PDFKit may replace when the
    /// display mode changes, so the observation is re-established whenever it is looked at.
    private func observeClipView() {
        guard let clipView = Self.scrollView(in: pdfView)?.contentView, clipView !== observedClipView else { return }
        let center = NotificationCenter.default
        if let observedClipView {
            center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        center.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    /// True once scroll events of PDFKit's internal scroll view are observed.
    var isObservingScrolling: Bool { observedClipView != nil }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = (view as? PDFView)?.documentView?.enclosingScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView ?? scrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    @objc private func pageDidChange(_ notification: Notification) {
        displayedPageIndex = currentPageIndex ?? 0
        observeClipView()
        reportPositionIfNeeded()
    }

    @objc private func scaleDidChange(_ notification: Notification) {
        reportPositionIfNeeded()
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        reportPositionIfNeeded()
    }

    /// Runs `work` when the view is in a window with a size, or after `attempts` retries (50 ms apart) regardless.
    /// The first try is on the next run loop turn.
    private func performAfterLayout(attempts: Int, delay: DispatchTimeInterval = .milliseconds(0), _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let size = self.pdfView.bounds.size
                let isLaidOut = self.pdfView.window != nil && size.width > 0 && size.height > 0
                if isLaidOut || attempts <= 0 {
                    work()
                } else {
                    self.performAfterLayout(attempts: attempts - 1, delay: Self.layoutRetryDelay, work)
                }
            }
        }
    }

    // MARK: - Outline

    private static func outlineItems(of parent: PDFOutline, in document: PDFDocument) -> [PDFOutlineItem] {
        (0..<parent.numberOfChildren).compactMap { index in
            guard let child = parent.child(at: index) else { return nil }
            let children = outlineItems(of: child, in: document)
            let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pageIndex = child.destination?.page.map { document.index(for: $0) }.flatMap { $0 == NSNotFound ? nil : $0 }
            return PDFOutlineItem(
                id: UUID(),
                title: label.isEmpty ? String(localized: "Untitled") : label,
                pageIndex: pageIndex,
                children: children.isEmpty ? nil : children
            )
        }
    }
}
