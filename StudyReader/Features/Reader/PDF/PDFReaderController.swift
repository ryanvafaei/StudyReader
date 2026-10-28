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
    /// In-document find and search-hit selection (T67).
    let findController: PDFFindController
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
    /// Draws and hit-tests the stored highlights and creates new ones (T59).
    @ObservationIgnored private(set) var highlightController: PDFHighlightController?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private weak var observedClipView: NSClipView?
    /// True once the saved position was restored and scroll events are reported.
    @ObservationIgnored private(set) var isTrackingPosition = false
    /// `load` gave up waiting for a window; `windowAttached` finishes the start.
    @ObservationIgnored private var pendingTrackingStart = false
    @ObservationIgnored private var lastReportedPosition: PDFPosition?
    /// Mirror of `AppSettings.invertPDFInDarkMode`; kept current by `setInversionEnabled(_:)` (PDFInversion.swift).
    @ObservationIgnored var invertSettingEnabled: Bool
    /// Whether the dark-mode filters are on; set by `setInverted(_:)` (PDFInversion.swift).
    @ObservationIgnored var isInverted = false

    init(model: ReaderModel) {
        self.model = model
        self.invertSettingEnabled = model.session.settings.invertPDFInDarkMode
        let pdfView = StudyPDFView(frame: .zero)
        self.pdfView = pdfView
        self.findController = PDFFindController(pdfView: pdfView)
        super.init()
        highlightController = PDFHighlightController(model: model, pdfView: pdfView)
        pdfView.onEffectiveAppearanceChange = { [weak self] in self?.refreshInversion() }
        pdfView.onWindowAttached = { [weak self] in self?.windowAttached() }
        pdfView.onSnapshotDrag = { [weak self] rect, start in self?.snapshotDragFinished(rect: rect, start: start) }
        pdfView.onSnapshotCancel = { [weak self] in self?.pdfView.endSnapshotMode() }
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
        pendingTrackingStart = false
        lastReportedPosition = model.initialPDFPosition
        pdfView.autoScales = true
        pdfView.document = loaded
        highlightController?.sync(with: model.highlights)
        refreshInversion()
        registerActions()

        performAfterLayout(attempts: Self.layoutRetryLimit) { [weak self] isLaidOut in
            guard let self else { return }
            if isLaidOut {
                restoreSavedPositionAndBeginTracking()
            } else {
                // No window yet: a later layout would report page 0 over the saved position. Wait for `windowAttached`.
                pendingTrackingStart = true
            }
        }
    }

    /// The step `load` runs once the view is laid out: apply the saved position, then start tracking.
    private func restoreSavedPositionAndBeginTracking() {
        pendingTrackingStart = false
        if let saved = model.initialPDFPosition {
            applyPosition(saved)
        }
        // Layout-induced scroll events before this point must not overwrite the saved position.
        Task { @MainActor [weak self] in
            self?.beginTrackingPosition()
        }
    }

    /// The PDF view moved into a window. If `load` gave up waiting for one, runs its restore-and-track step once the
    /// view has a size.
    private func windowAttached() {
        guard pendingTrackingStart else { return }
        performAfterLayout(attempts: Self.layoutRetryLimit) { [weak self] isLaidOut in
            guard let self, isLaidOut, pendingTrackingStart else { return }
            restoreSavedPositionAndBeginTracking()
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
        model.engineActions.startSnapshot = { [weak self] in self?.toggleSnapshotMode() }
        model.engineActions.findInDocument = { [weak self] in self?.findController.show() }
    }

    /// Called when the tab goes away: leaves snapshot mode, cancels a running capture and drops the highlight
    /// controller's undo action.
    func tearDown() {
        pdfView.endSnapshotMode()
        snapshotTask?.cancel()
        snapshotTask = nil
        highlightController?.tearDown()
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

    // MARK: - Snapshot (F-08)

    /// The camera button and ⌃⌘S: enters snapshot mode, or leaves it when it is already on.
    func toggleSnapshotMode() {
        if pdfView.isSnapshotModeActive {
            pdfView.endSnapshotMode()
        } else if document != nil {
            pdfView.beginSnapshotMode()
        }
    }

    /// The drag ended: leaves the mode, converts the rect (view space) to page space on the page under the start
    /// point, clips it, renders it off the main actor from the file on disk and stores it as an image highlight in
    /// the current color. A drag off the pages or under 10 x 10 pt is ignored silently.
    private func snapshotDragFinished(rect: CGRect, start: CGPoint) {
        pdfView.endSnapshotMode()
        guard let document, let url = model.fileURL,
              let page = pdfView.page(for: start, nearest: false) else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        let cropBox = page.bounds(for: .cropBox)
        guard let clipped = SnapshotService.clippedRect(pdfView.convert(rect, to: page), pageBounds: cropBox) else { return }
        // Top of the clipped rect measured from the crop box's bottom (`clipped.maxY - cropBox.minY`), the same
        // convention as PDFAnchorBuilder's `firstTop` for text highlights (ARCHITECTURE §5.5).
        let positionKey = PDFAnchorBuilder.positionKey(
            pageIndex: pageIndex,
            pageHeight: Double(cropBox.height),
            topOfFirstRect: Double(clipped.maxY - cropBox.minY)
        )
        let new = NewImageHighlight(
            documentId: model.documentId,
            pageIndex: pageIndex,
            rect: CGRectCodable(clipped),
            positionKey: positionKey,
            color: model.session.settings.currentColor,
            pngData: Data()
        )
        snapshotTask?.cancel()
        snapshotTask = Task { @MainActor [weak self] in
            let png = await Task.detached { try? SnapshotService.renderPNG(fileAt: url, pageIndex: pageIndex, rect: clipped) }.value
            guard let self, !Task.isCancelled else { return }
            guard let png else {
                model.snapshotRenderFailed()
                return
            }
            var captured = new
            captured.pngData = png
            await model.createSnapshot(captured)
        }
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

    /// Applies a `.page`, `.highlight` or `.searchHit` location the model holds and consumes it. A search hit opens
    /// the page and selects the first match of the query's first positive term on it (the view stays on the page when
    /// the term isn't found there). `.documentNote` is the window's.
    /// Before the saved position is restored the call does nothing; `beginTrackingPosition` applies it afterwards.
    /// A `.highlight` location whose highlight isn't loaded yet stays pending; `highlightsChanged()` retries it. Once
    /// the highlights have loaded and it isn't among them (it was deleted), the location is consumed.
    func applyPendingLocation() {
        guard isTrackingPosition else { return }
        switch model.pendingLocation {
        case .page(let index):
            go(toPage: index)
        case .highlight(let id):
            guard highlightController?.reveal(highlightId: id) == true || model.hasLoadedHighlights else { return }
        case .searchHit(let unitIndex, let query):
            go(toPage: unitIndex)
            if let term = SearchQueryParser.firstPositiveTerm(in: query) {
                findController.selectFirstMatch(of: term, onPage: unitIndex)
            }
        default:
            return
        }
        model.consumeLocation()
        reportPositionIfNeeded()
    }

    /// `model.highlights` changed: redraw the annotations, then retry a pending `.highlight` location.
    func highlightsChanged() {
        highlightController?.sync(with: model.highlights)
        applyPendingLocation()
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
        performAfterLayout(attempts: Self.layoutRetryLimit) { [weak self] _ in
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

    /// Runs `work` when the view is in a window with a size (`isLaidOut` true), or after `attempts` retries (50 ms
    /// apart) with `isLaidOut` false. The first try is on the next run loop turn.
    private func performAfterLayout(
        attempts: Int,
        delay: DispatchTimeInterval = .milliseconds(0),
        _ work: @escaping @MainActor (_ isLaidOut: Bool) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let size = self.pdfView.bounds.size
                let isLaidOut = self.pdfView.window != nil && size.width > 0 && size.height > 0
                if isLaidOut || attempts <= 0 {
                    work(isLaidOut)
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
