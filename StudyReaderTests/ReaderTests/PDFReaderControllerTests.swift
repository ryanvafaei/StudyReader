import AppKit
import Foundation
import PDFKit
import Testing
@testable import StudyReader

@MainActor
@Suite("PDFReaderController")
struct PDFReaderControllerTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000F5"
    private static let viewSize = CGSize(width: 600, height: 800)

    /// Everything one test needs. The window is borderless and never shown; it gives the PDF view a size and a
    /// window so layout runs.
    private struct Harness {
        let session: AppSession
        let model: ReaderModel
        let controller: PDFReaderController
        let window: NSWindow
        let url: URL
    }

    private static func makeHarness(
        fileData: Data = PDFFixtureBuilder.plainMultiPage(pageCount: 5),
        savedPosition: PDFPosition? = nil,
        attachWindow: Bool = true
    ) async throws -> Harness {
        let session = try ReaderTestSupport.makeSession()
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: documentId))
        _ = try environment.fileStore.createDocumentFolder(documentId: documentId)
        let url = try environment.fileStore.originalFileURL(documentId: documentId, fileType: .pdf)
        try fileData.write(to: url)
        if let savedPosition {
            try await environment.documentRepository.updatePDFPosition(id: documentId, position: savedPosition, progress: 0.5)
        }

        let model = ReaderModel(documentId: documentId, session: session)
        await model.load()
        let controller = PDFReaderController(model: model)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        if attachWindow {
            window.contentView = controller.pdfView
            controller.pdfView.frame = CGRect(origin: .zero, size: viewSize)
            window.layoutIfNeeded()
        }
        return Harness(session: session, model: model, controller: controller, window: window, url: url)
    }

    /// Suspends the test so the main queue runs (the controller's layout waits and PDFKit's notifications). Spinning
    /// the run loop inside the test doesn't work: the test itself runs in a main-queue block, and a serial queue
    /// doesn't start another block until the current one returns.
    private static func settle(_ seconds: Double = 0.3) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    @Test(.timeLimit(.minutes(1)))
    func snapshotModeTogglesAndEscapeCancels() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        #expect(harness.model.engineActions.startSnapshot == nil)
        harness.controller.load(url: harness.url)
        let start = try #require(harness.model.engineActions.startSnapshot)

        start()
        #expect(harness.controller.pdfView.isSnapshotModeActive)
        start()
        #expect(!harness.controller.pdfView.isSnapshotModeActive)

        start()
        harness.controller.pdfView.onSnapshotCancel?()
        #expect(!harness.controller.pdfView.isSnapshotModeActive)

        start()
        harness.controller.tearDown()
        #expect(!harness.controller.pdfView.isSnapshotModeActive)
    }

    @Test(.timeLimit(.minutes(1)))
    func snapshotDragCreatesImageHighlight() async throws {
        let harness = try await Self.makeHarness(fileData: PDFFixtureBuilder.coloredRegion())
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)
        try await Self.settle()
        let pdfView = harness.controller.pdfView
        let page = try #require(pdfView.document?.page(at: 0))
        let pageRect = PDFFixtureBuilder.coloredRect
        let viewRect = pdfView.convert(pageRect, from: page)
        harness.model.engineActions.startSnapshot?()
        #expect(pdfView.isSnapshotModeActive)

        pdfView.onSnapshotDrag?(viewRect, CGPoint(x: viewRect.midX, y: viewRect.midY))
        #expect(!pdfView.isSnapshotModeActive)

        let repository = harness.session.environment.highlightRepository
        var rows: [Highlight] = []
        for _ in 0..<100 where rows.isEmpty {
            try await Self.settle(0.05)
            rows = try await repository.fetchForDocument(Self.documentId)
        }
        let highlight = try #require(rows.first, "no image highlight was stored")
        #expect(highlight.kind == .image)
        #expect(highlight.color == harness.session.settings.currentColor)
        guard case .image(let anchor) = highlight.anchor else {
            Issue.record("expected an image anchor")
            return
        }
        #expect(anchor.pageIndex == 0)
        #expect(abs(anchor.rect.x - pageRect.minX) < 1.5 && abs(anchor.rect.y - pageRect.minY) < 1.5, "rect: \(anchor.rect)")
        #expect(abs(anchor.rect.width - pageRect.width) < 1.5 && abs(anchor.rect.height - pageRect.height) < 1.5)
        let imagePath = try #require(highlight.imagePath)
        let imageURL = try #require(harness.session.environment.fileStore.url(forRelativePath: imagePath))
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func tinySnapshotDragIsIgnored() async throws {
        let harness = try await Self.makeHarness(fileData: PDFFixtureBuilder.coloredRegion())
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)
        try await Self.settle()
        let pdfView = harness.controller.pdfView
        let page = try #require(pdfView.document?.page(at: 0))
        let viewRect = pdfView.convert(CGRect(x: 100, y: 100, width: 4, height: 4), from: page)
        harness.model.engineActions.startSnapshot?()
        pdfView.onSnapshotDrag?(viewRect, CGPoint(x: viewRect.midX, y: viewRect.midY))
        #expect(!pdfView.isSnapshotModeActive)
        try await Self.settle(0.3)
        let rows = try await harness.session.environment.highlightRepository.fetchForDocument(Self.documentId)
        #expect(rows.isEmpty)
        #expect(harness.model.transientMessage == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadsAndRegistersActions() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }

        harness.controller.load(url: harness.url)

        #expect(harness.controller.pageCount == 5)
        #expect(harness.model.engineActions.zoomIn != nil)
        #expect(harness.model.engineActions.zoomOut != nil)
        #expect(harness.model.engineActions.actualSize != nil)
        #expect(harness.model.engineActions.fitWidth != nil)
        #expect(harness.model.engineActions.toggleSinglePage != nil)
        #expect(harness.model.engineActions.toggleThumbnails != nil)
        #expect(harness.controller.currentPageIndex == 0)
        #expect(harness.model.engineActions.currentPageIndex?() == 0)
        #expect(harness.model.isDocumentAvailable)
        #expect(harness.controller.pdfView.displayMode == .singlePageContinuous)
        #expect(harness.controller.pdfView.displaysPageBreaks)
    }

    @Test(.timeLimit(.minutes(1)))
    func restoresSavedPosition() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)

        harness.controller.restore(PDFPosition(pageIndex: 2, offsetY: 500))
        try await Self.settle(0.2)

        let position = try #require(harness.controller.currentPosition())
        #expect(position.pageIndex == 2)
        #expect(abs(position.offsetY - 500) < 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadRestoresThePositionStoredInTheLibrary() async throws {
        let harness = try await Self.makeHarness(savedPosition: PDFPosition(pageIndex: 3, offsetY: 400))
        defer { ReaderTestSupport.cleanUp(harness.session) }

        harness.controller.load(url: harness.url)
        try await Self.settle(0.3)

        let position = try #require(harness.controller.currentPosition())
        #expect(position.pageIndex == 3)
        #expect(abs(position.offsetY - 400) < 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func trackingWaitsForAWindow() async throws {
        let saved = PDFPosition(pageIndex: 1, offsetY: 300)
        let harness = try await Self.makeHarness(
            fileData: PDFFixtureBuilder.plainMultiPage(pageCount: 3), savedPosition: saved, attachWindow: false)
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let controller = harness.controller
        #expect(controller.pdfView.window == nil)
        controller.load(url: harness.url)

        // The retry limit (40 x 50 ms) passes without a window: tracking must not have started.
        try await Self.settle(3)
        #expect(!controller.isTrackingPosition)
        await harness.model.flushPosition()
        #expect((await ReaderTestSupport.row(harness.session, id: Self.documentId))?.pdfPosition == saved)

        harness.window.contentView = controller.pdfView
        controller.pdfView.frame = CGRect(origin: .zero, size: Self.viewSize)
        harness.window.layoutIfNeeded()
        for _ in 0..<80 where !controller.isTrackingPosition {
            try await Self.settle(0.05)
        }
        #expect(controller.isTrackingPosition)
        try await Self.settle(0.2)
        // `currentPosition` is the page of the visible top, the same measure as the saved position;
        // `currentPageIndex` (PDFKit's `currentPage`) isn't guaranteed to match it.
        let position = try #require(controller.currentPosition())
        #expect(position.pageIndex == 1)
        #expect(abs(position.offsetY - saved.offsetY) < 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func scrollingSavesThePositionAfterTheInitialRestore() async throws {
        let harness = try await Self.makeHarness(savedPosition: PDFPosition(pageIndex: 1, offsetY: 300))
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)
        try await Self.settle(0.3)
        #expect((await ReaderTestSupport.row(harness.session, id: Self.documentId))?.pdfPosition?.pageIndex == 1)

        #expect(harness.controller.isObservingScrolling, "PDFKit's scroll view wasn't found.")
        harness.controller.go(toPage: 3)
        try await Self.settle(0.3)
        #expect(harness.controller.currentPosition()?.pageIndex == 3)
        await harness.model.flushPosition()

        let saved = await ReaderTestSupport.row(harness.session, id: Self.documentId)?.pdfPosition
        #expect(saved?.pageIndex == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func zoomCommands() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let controller = harness.controller
        controller.load(url: harness.url)
        try await Self.settle(0.2)

        controller.actualSize()
        #expect(controller.pdfView.scaleFactor == 1)
        #expect(controller.pdfView.autoScales == false)

        controller.zoomIn()
        #expect(controller.pdfView.scaleFactor > 1)
        #expect(controller.pdfView.autoScales == false)

        controller.zoomOut()
        controller.zoomOut()
        #expect(controller.pdfView.scaleFactor < 1)

        let expected = try #require(controller.fitWidthScale)
        controller.fitWidth()
        #expect(abs(controller.pdfView.scaleFactor - expected) < 0.01)
        #expect(controller.pdfView.autoScales == false)
        // A 612 pt wide page in a 600 pt wide view: a little under 1, never the 5x or 0.25x limits.
        #expect(expected > 0.8 && expected < 1.0)
    }

    @Test
    func fitWidthScaleSubtractsTheMargins() {
        #expect(PDFReaderController.fitWidthScale(visibleWidth: 616, margins: 16, pageWidth: 600) == 1)
        #expect(PDFReaderController.fitWidthScale(visibleWidth: 316, margins: 16, pageWidth: 600) == 0.5)
        #expect(PDFReaderController.fitWidthScale(visibleWidth: 600, margins: 16, pageWidth: 0) == nil)
        #expect(PDFReaderController.fitWidthScale(visibleWidth: 10, margins: 16, pageWidth: 600) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func singlePageToggleSwitchesTheDisplayMode() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)
        try await Self.settle(0.2)

        harness.model.engineActions.toggleSinglePage?()
        #expect(harness.controller.pdfView.displayMode == .singlePage)
        #expect(harness.controller.isSinglePage)

        harness.controller.setSinglePage(false)
        #expect(harness.controller.pdfView.displayMode == .singlePageContinuous)
    }

    @Test(.timeLimit(.minutes(1)))
    func thumbnailActionTogglesTheColumn() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)

        #expect(harness.controller.showsThumbnails == false)
        harness.model.engineActions.toggleThumbnails?()
        #expect(harness.controller.showsThumbnails)
        harness.model.engineActions.toggleThumbnails?()
        #expect(harness.controller.showsThumbnails == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func pagePendingLocationIsAppliedAndConsumed() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)
        try await Self.settle(0.3)

        harness.model.navigate(to: .page(3))
        harness.controller.applyPendingLocation()
        try await Self.settle(0.2)

        #expect(harness.model.pendingLocation == nil)
        #expect(harness.controller.currentPosition()?.pageIndex == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func deletedHighlightLocationIsConsumed() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)
        try await Self.settle(0.3)

        harness.model.navigate(to: .highlight("missing-id"))
        harness.controller.applyPendingLocation()
        #expect(harness.model.pendingLocation == .highlight("missing-id"))

        let observer = Task { await harness.model.observeHighlights() }
        defer { observer.cancel() }
        let loaded = await ReaderTestSupport.waitUntil { harness.model.hasLoadedHighlights }
        #expect(loaded)

        harness.controller.applyPendingLocation()
        #expect(harness.model.pendingLocation == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func outlineIsEmptyForFixture() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(url: harness.url)

        #expect(harness.controller.outline.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func damagedFileFailsTheModel() async throws {
        let harness = try await Self.makeHarness(fileData: Data("not a pdf".utf8))
        defer { ReaderTestSupport.cleanUp(harness.session) }

        harness.controller.load(url: harness.url)

        #expect(harness.model.state == .failed("The document couldn't be opened."))
        #expect(harness.model.engineActions.zoomIn == nil)
        #expect(harness.model.engineActions.toggleThumbnails == nil)
        #expect(harness.model.isDocumentAvailable == false)
        #expect(harness.model.isRightPanelVisible == false)
        #expect(harness.controller.document == nil)
    }
}
