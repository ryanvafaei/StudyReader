import AppKit
import Foundation
import PDFKit
import Testing
@testable import StudyReader

@MainActor
@Suite("Find")
struct FindTests {
    private static let pdfDocumentId = "30000000-0000-0000-0000-0000000000A7"
    private static let markdownDocumentId = "30000000-0000-0000-0000-0000000000A8"
    private static let pdfViewSize = CGSize(width: 600, height: 800)
    private static let textViewSize = CGSize(width: 900, height: 700)

    private static func settle(_ seconds: Double = 0.3) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private static func pageIndex(of selection: PDFSelection?, in document: PDFDocument?) -> Int? {
        guard let page = selection?.pages.first, let document else { return nil }
        return document.index(for: page)
    }

    // MARK: - PDF find

    /// A `StudyPDFView` showing a generated PDF in an unshown borderless window.
    private static func makePDFView(pageCount: Int) throws -> (view: StudyPDFView, window: NSWindow, document: PDFDocument) {
        let view = StudyPDFView(frame: CGRect(origin: .zero, size: pdfViewSize))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: pdfViewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.plainMultiPage(pageCount: pageCount)))
        view.document = document
        window.layoutIfNeeded()
        return (view, window, document)
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfFindCountsAndSteps() throws {
        let fixture = try Self.makePDFView(pageCount: 3)
        let find = PDFFindController(pdfView: fixture.view)

        find.query = "fox"
        find.search()
        #expect(find.matchCount == 30, "matchCount: \(find.matchCount)")
        #expect(find.currentIndex == 0)
        #expect(fixture.view.highlightedSelections?.count == 30)
        #expect(Self.pageIndex(of: fixture.view.currentSelection, in: fixture.document) == 0)

        find.next()
        #expect(find.currentIndex == 1)
        find.previous()
        #expect(find.currentIndex == 0)
        find.previous()
        #expect(find.currentIndex == 29, "currentIndex: \(String(describing: find.currentIndex))")
        #expect(Self.pageIndex(of: fixture.view.currentSelection, in: fixture.document) == 2)
        find.next()
        #expect(find.currentIndex == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfFindIsCaseInsensitiveAndClearsOnClose() throws {
        let fixture = try Self.makePDFView(pageCount: 2)
        let find = PDFFindController(pdfView: fixture.view)
        find.show()
        #expect(find.isVisible)

        find.query = "QUICK"
        find.search()
        #expect(find.matchCount == 20)

        find.query = "zebra"
        find.search()
        #expect(find.matchCount == 0)
        #expect(find.currentIndex == nil)
        find.next()
        find.previous()
        #expect(find.currentIndex == nil)

        find.query = "fox"
        find.search()
        #expect(find.matchCount == 20)
        find.close()
        #expect(!find.isVisible)
        #expect(find.matchCount == 0)
        #expect(find.currentIndex == nil)
        #expect((fixture.view.highlightedSelections ?? []).isEmpty)

        find.query = "   "
        find.search()
        #expect(find.matchCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfFindStartsAtTheCurrentPage() async throws {
        let fixture = try Self.makePDFView(pageCount: 3)
        let find = PDFFindController(pdfView: fixture.view)
        fixture.view.go(to: try #require(fixture.document.page(at: 1)))
        try await Self.settle()

        find.query = "line 4"
        find.search()
        #expect(find.matchCount == 3)
        #expect(Self.pageIndex(of: fixture.view.currentSelection, in: fixture.document) == 1)
        #expect(find.currentIndex == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfSelectFirstMatchOnPage() throws {
        let fixture = try Self.makePDFView(pageCount: 3)
        let find = PDFFindController(pdfView: fixture.view)

        #expect(find.selectFirstMatch(of: "line 5", onPage: 2))
        #expect(Self.pageIndex(of: fixture.view.currentSelection, in: fixture.document) == 2)
        #expect(fixture.view.currentSelection?.string?.lowercased() == "line 5")

        #expect(!find.selectFirstMatch(of: "zebra", onPage: 2))
        #expect(!find.selectFirstMatch(of: "fox", onPage: 9))
        #expect(!find.selectFirstMatch(of: "  ", onPage: 0))
    }

    @Test(.timeLimit(.minutes(1)))
    func pdfSelectFirstMatchTreatsTheTermAsPlainText() throws {
        let fixture = try Self.makePDFView(pageCount: 1)
        let find = PDFFindController(pdfView: fixture.view)

        #expect(!find.selectFirstMatch(of: "l.ne", onPage: 0))
        #expect(!find.selectFirstMatch(of: "(", onPage: 0))
        #expect(find.selectFirstMatch(of: "PAGE 1 LINE 1:", onPage: 0))
    }

    // MARK: - PDF search-hit location

    private struct PDFHarness {
        let session: AppSession
        let model: ReaderModel
        let controller: PDFReaderController
        let window: NSWindow
    }

    private static func makePDFHarness() async throws -> PDFHarness {
        let session = try ReaderTestSupport.makeSession()
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: pdfDocumentId))
        _ = try environment.fileStore.createDocumentFolder(documentId: pdfDocumentId)
        let url = try environment.fileStore.originalFileURL(documentId: pdfDocumentId, fileType: .pdf)
        try PDFFixtureBuilder.plainMultiPage(pageCount: 5).write(to: url)

        let model = ReaderModel(documentId: pdfDocumentId, session: session)
        await model.load()
        let controller = PDFReaderController(model: model)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: pdfViewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.pdfView
        controller.pdfView.frame = CGRect(origin: .zero, size: pdfViewSize)
        window.layoutIfNeeded()
        controller.load(url: url)
        try await settle(0.5)
        return PDFHarness(session: session, model: model, controller: controller, window: window)
    }

    @Test(.timeLimit(.minutes(1)))
    func searchHitLocationConsumed() async throws {
        let harness = try await Self.makePDFHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        #expect(harness.model.engineActions.findInDocument != nil)

        harness.model.navigate(to: .searchHit(unitIndex: 1, query: "\"page 2 line 3\""))
        harness.controller.applyPendingLocation()
        try await Self.settle(0.2)

        #expect(harness.controller.currentPageIndex == 1, "page: \(String(describing: harness.controller.currentPageIndex))")
        let selection = harness.controller.pdfView.currentSelection
        #expect(selection?.string?.contains("Page 2 line 3") == true, "selection: \(String(describing: selection?.string))")
        #expect(harness.model.pendingLocation == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func searchHitWithoutAMatchKeepsThePage() async throws {
        let harness = try await Self.makePDFHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }

        harness.model.navigate(to: .searchHit(unitIndex: 2, query: "-fox zebra"))
        harness.controller.applyPendingLocation()
        try await Self.settle(0.2)
        #expect(harness.controller.currentPageIndex == 2)
        #expect(harness.controller.pdfView.currentSelection?.string?.isEmpty ?? true)
        #expect(harness.model.pendingLocation == nil)

        harness.model.navigate(to: .searchHit(unitIndex: 3, query: "-fox"))
        harness.controller.applyPendingLocation()
        try await Self.settle(0.2)
        #expect(harness.controller.currentPageIndex == 3)
        #expect(harness.model.pendingLocation == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func findActionShowsTheBar() async throws {
        let harness = try await Self.makePDFHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        #expect(!harness.controller.findController.isVisible)

        harness.model.engineActions.findInDocument?()
        #expect(harness.controller.findController.isVisible)
    }

    // MARK: - Text find

    private struct TextHarness {
        let session: AppSession
        let model: ReaderModel
        let controller: TextReaderController
        let window: NSWindow
        let rendered: RenderedMarkdown
    }

    private static func makeTextHarness() async throws -> TextHarness {
        let session = try ReaderTestSupport.makeSession()
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: markdownDocumentId, fileType: .markdown))
        _ = try environment.fileStore.createDocumentFolder(documentId: markdownDocumentId)
        let url = try environment.fileStore.originalFileURL(documentId: markdownDocumentId, fileType: .markdown)
        let markdown = try MarkdownFixtures.string("all-elements")
        try Data(markdown.utf8).write(to: url)
        let model = ReaderModel(documentId: markdownDocumentId, session: session)
        await model.load()
        let rendered = MarkdownRenderer.render(MarkdownDocumentSource(
            markdown: markdown,
            documentId: markdownDocumentId,
            fileStore: environment.fileStore
        ))
        let controller = TextReaderController(model: model)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: textViewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.scrollView
        controller.scrollView.frame = CGRect(origin: .zero, size: textViewSize)
        window.layoutIfNeeded()
        return TextHarness(session: session, model: model, controller: controller, window: window, rendered: rendered)
    }

    @Test(.timeLimit(.minutes(1)))
    func textSelectFirstMatch() async throws {
        let harness = try await Self.makeTextHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(harness.rendered.attributedString)
        try await Self.settle()
        let text = harness.rendered.string as NSString
        let first = text.range(of: "item", options: .caseInsensitive)
        let last = text.range(of: "item", options: [.caseInsensitive, .backwards])
        try #require(first.location != NSNotFound && last.location > first.location)

        #expect(harness.controller.selectFirstMatch(of: "item", from: 0))
        #expect(harness.controller.textView.selectedRange() == first)
        #expect(text.substring(with: first).lowercased() == "item")

        #expect(harness.controller.selectFirstMatch(of: "ITEM", from: first.location + 1))
        let second = harness.controller.textView.selectedRange()
        #expect(second.location > first.location)

        #expect(harness.controller.selectFirstMatch(of: "item", from: NSMaxRange(last)))
        #expect(harness.controller.textView.selectedRange() == first, "wrapped selection: \(harness.controller.textView.selectedRange())")

        harness.controller.textView.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(!harness.controller.selectFirstMatch(of: "zebra", from: 0))
        #expect(harness.controller.textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test(.timeLimit(.minutes(1)))
    func markdownSearchHitSelectsTheFirstMatchInTheSection() async throws {
        let harness = try await Self.makeTextHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let coordinator = MarkdownReaderCoordinator(model: harness.model)
        harness.window.contentView = coordinator.controller.scrollView
        coordinator.controller.scrollView.frame = CGRect(origin: .zero, size: Self.textViewSize)
        coordinator.loadIfNeeded()
        try await Self.settle(0.8)
        let rendered = try #require(coordinator.rendered)
        try #require(rendered.sections.count >= 2)
        let section = rendered.sections[1]

        harness.model.navigate(to: .searchHit(unitIndex: 1, query: "-zebra Item"))
        coordinator.applyPendingLocation()

        let selected = coordinator.controller.textView.selectedRange()
        #expect(NSLocationInRange(selected.location, section), "selection \(selected) section \(section)")
        #expect((rendered.string as NSString).substring(with: selected).lowercased() == "item")
        #expect(harness.model.pendingLocation == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func markdownSearchHitWithoutAMatchOrWithABadUnitIsHarmless() async throws {
        let harness = try await Self.makeTextHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let coordinator = MarkdownReaderCoordinator(model: harness.model)
        harness.window.contentView = coordinator.controller.scrollView
        coordinator.controller.scrollView.frame = CGRect(origin: .zero, size: Self.textViewSize)
        coordinator.loadIfNeeded()
        try await Self.settle(0.8)

        harness.model.navigate(to: .searchHit(unitIndex: 1, query: "zebra"))
        coordinator.applyPendingLocation()
        #expect(coordinator.controller.textView.selectedRange().length == 0)
        #expect(harness.model.pendingLocation == nil)

        harness.model.navigate(to: .searchHit(unitIndex: 99, query: "-item"))
        coordinator.applyPendingLocation()
        #expect(harness.model.pendingLocation == nil)

        harness.model.navigate(to: .searchHit(unitIndex: 99, query: "item"))
        coordinator.applyPendingLocation()
        #expect(coordinator.controller.textView.selectedRange().length == 4)
        #expect(harness.model.pendingLocation == nil)
    }

    // MARK: - Plain text matching

    @Test
    func plainTextFinderMatchesCaseDiacriticsAndLineBreaks() throws {
        let text = "Alpha café\nbeta  gamma.\u{2028}Delta" as NSString
        #expect(PlainTextFinder.firstRange(of: "CAFE", in: text) == NSRange(location: 6, length: 4))
        #expect(PlainTextFinder.firstRange(of: "café beta", in: text) == NSRange(location: 6, length: 9))
        #expect(PlainTextFinder.firstRange(of: "beta gamma", in: text) == NSRange(location: 11, length: 11))
        #expect(PlainTextFinder.firstRange(of: "gamma. delta", in: text) == NSRange(location: 17, length: 12))
        #expect(PlainTextFinder.firstRange(of: "alphacafe", in: text) == nil)
        #expect(PlainTextFinder.firstRange(of: "", in: text) == nil)
        #expect(PlainTextFinder.firstRange(of: " \n ", in: text) == nil)
    }

    @Test
    func plainTextFinderWrapsAndIgnoresPatternSyntax() {
        let text = "ab ab abc a.c" as NSString
        #expect(PlainTextFinder.firstRange(of: "ab", in: text, from: 1) == NSRange(location: 3, length: 2))
        #expect(PlainTextFinder.firstRange(of: "ab", in: text, from: 12) == NSRange(location: 0, length: 2))
        #expect(PlainTextFinder.firstRange(of: "ab", in: text, from: 500) == NSRange(location: 0, length: 2))
        #expect(PlainTextFinder.firstRange(of: "ab", in: text, from: -5) == NSRange(location: 0, length: 2))
        #expect(PlainTextFinder.firstRange(of: "a.c", in: text) == NSRange(location: 10, length: 3))
        #expect(PlainTextFinder.firstRange(of: ".*", in: text) == nil)
        #expect(PlainTextFinder.firstRange(of: "ab ab abcd", in: text) == nil)
    }
}
