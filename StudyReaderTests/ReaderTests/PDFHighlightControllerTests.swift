import AppKit
import Foundation
import PDFKit
import Testing
@testable import StudyReader

@MainActor
@Suite("PDFHighlightController")
struct PDFHighlightControllerTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000F9"
    private static let viewSize = CGSize(width: 600, height: 800)

    /// Everything one test needs. The window is borderless and never shown; it gives the PDF view a size.
    private struct Harness {
        let session: AppSession
        let model: ReaderModel
        let pdfView: StudyPDFView
        let controller: PDFHighlightController
        let window: NSWindow
        let document: PDFDocument
    }

    private static func makeHarness() async throws -> Harness {
        let session = try ReaderTestSupport.makeSession()
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: documentId))
        _ = try environment.fileStore.createDocumentFolder(documentId: documentId)
        let url = try environment.fileStore.originalFileURL(documentId: documentId, fileType: .pdf)
        try PDFFixtureBuilder.plainMultiPage(pageCount: 3).write(to: url)

        let model = ReaderModel(documentId: documentId, session: session)
        await model.load()
        let pdfView = StudyPDFView(frame: CGRect(origin: .zero, size: viewSize))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = pdfView
        let document = try #require(PDFDocument(url: url))
        pdfView.document = document
        window.layoutIfNeeded()
        let controller = PDFHighlightController(model: model, pdfView: pdfView)
        return Harness(
            session: session, model: model, pdfView: pdfView, controller: controller, window: window, document: document
        )
    }

    private static func selection(_ document: PDFDocument, text: String, page index: Int) throws -> PDFSelection {
        let page = try #require(document.page(at: index))
        let pageText = try #require(page.string) as NSString
        let range = pageText.range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(page.selection(for: range))
    }

    private static func crossPageSelection(_ document: PDFDocument) throws -> PDFSelection {
        let first = try #require(document.page(at: 0))
        let second = try #require(document.page(at: 1))
        let firstText = try #require(first.string) as NSString
        let secondText = try #require(second.string) as NSString
        let start = firstText.range(of: "line 9")
        let end = secondText.range(of: "line 2")
        try #require(start.location != NSNotFound && end.location != NSNotFound)
        return try #require(document.selection(
            from: first, atCharacterIndex: start.location,
            to: second, atCharacterIndex: NSMaxRange(end) - 1))
    }

    private static func highlight(
        id: String,
        selection: PDFSelection,
        document: PDFDocument,
        color: HighlightColor = .yellow,
        createdAt: Date = TestData.referenceDate
    ) throws -> Highlight {
        let result = try #require(PDFAnchorBuilder.anchor(for: selection, in: document))
        return Highlight(
            id: id, documentId: documentId, kind: .text, view: .pdf, color: color,
            text: result.text, richText: RichTextMarkdown.escape(result.text), pageIndex: result.firstPageIndex,
            positionKey: result.positionKey, anchor: .pdf(result.anchor), createdAt: createdAt, updatedAt: createdAt)
    }

    private static func annotations(_ document: PDFDocument) -> [StudyHighlightAnnotation] {
        (0..<document.pageCount).flatMap { index in
            (document.page(at: index)?.annotations ?? []).compactMap { $0 as? StudyHighlightAnnotation }
        }
    }

    private static func isSameColor(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let a = lhs.usingColorSpace(.sRGB), let b = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01 && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }

    // MARK: - Tests

    @Test(.timeLimit(.minutes(1)))
    func syncAddsAndRemovesAnnotations() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let document = harness.document
        let single = try Self.highlight(
            id: "single", selection: Self.selection(document, text: "line 1: The quick", page: 0), document: document)
        let cross = try Self.highlight(
            id: "cross", selection: Self.crossPageSelection(document), document: document,
            createdAt: TestData.referenceDate.addingTimeInterval(1))

        harness.controller.sync(with: [single, cross])
        #expect(harness.controller.annotationCount == 3, "count: \(harness.controller.annotationCount)")
        #expect(Self.annotations(document).count == 3)

        var recolored = single
        recolored.color = .blue
        harness.controller.sync(with: [recolored, cross])
        #expect(harness.controller.annotationCount == 3)
        let expected = PDFHighlightController.annotationColor(for: .blue)
        let singleAnnotations = Self.annotations(document).filter { $0.highlightId == "single" }
        #expect(singleAnnotations.count == 1)
        #expect(singleAnnotations.allSatisfy { Self.isSameColor($0.color, expected) }, "colors: \(singleAnnotations.map(\.color))")

        harness.controller.sync(with: [recolored])
        #expect(harness.controller.annotationCount == 1)
        #expect(Self.annotations(document).map(\.highlightId) == ["single"])

        harness.controller.sync(with: [])
        #expect(harness.controller.annotationCount == 0)
        #expect(Self.annotations(document).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func recoloringAnOlderHighlightKeepsNewerOnTop() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let document = harness.document
        let selection = try Self.selection(document, text: "line 1: The quick", page: 0)
        let older = try Self.highlight(id: "older", selection: selection, document: document)
        let newer = try Self.highlight(
            id: "newer", selection: selection, document: document,
            createdAt: TestData.referenceDate.addingTimeInterval(1))
        harness.controller.sync(with: [older, newer])
        #expect(Self.annotations(document).map(\.highlightId) == ["older", "newer"])

        var recolored = older
        recolored.color = .pink
        harness.controller.sync(with: [recolored, newer])
        #expect(Self.annotations(document).map(\.highlightId) == ["older", "newer"])
        #expect(harness.controller.annotationCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func newerHighlightWinsHitTest() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let document = harness.document
        let selection = try Self.selection(document, text: "line 1: The quick", page: 0)
        let older = try Self.highlight(id: "older", selection: selection, document: document)
        let newer = try Self.highlight(
            id: "newer", selection: selection, document: document,
            createdAt: TestData.referenceDate.addingTimeInterval(1))
        harness.controller.sync(with: [newer, older])

        let rect = try #require(Self.annotations(document).first?.bounds)
        let inside = CGPoint(x: rect.midX, y: rect.midY)
        #expect(harness.controller.highlightIds(at: inside, onPage: 0) == ["newer", "older"])
        #expect(harness.controller.highlightIds(at: inside, onPage: 1).isEmpty)
        let outside = CGPoint(x: rect.maxX + 50, y: rect.midY)
        #expect(harness.controller.highlightIds(at: outside, onPage: 0).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func newHighlightUsesEscapedText() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let selection = try Self.selection(harness.document, text: "line 1: The quick", page: 0)

        let new = try #require(harness.controller.newHighlight(for: selection, color: .green))
        let anchor = try #require(PDFAnchorBuilder.anchor(for: selection, in: harness.document))
        #expect(new.richText == RichTextMarkdown.escape(new.text))
        #expect(new.text == anchor.text)
        #expect(new.view == .pdf)
        #expect(new.pageIndex == 0)
        #expect(new.positionKey == anchor.positionKey)
        #expect(new.color == .green)
        #expect(new.documentId == Self.documentId)
        #expect(new.anchor == .pdf(anchor.anchor))
    }

    @Test(.timeLimit(.minutes(1)))
    func orphanedAndImageHighlightsNotDrawn() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let document = harness.document
        var orphaned = try Self.highlight(
            id: "orphaned", selection: Self.selection(document, text: "line 1: The quick", page: 0), document: document)
        orphaned.anchorStatus = .orphaned
        let image = Highlight(
            id: "image", documentId: Self.documentId, kind: .image, view: .pdf, pageIndex: 0, positionKey: 0,
            anchor: .image(ImageAnchor(pageIndex: 0, rect: CGRectCodable(x: 10, y: 10, width: 100, height: 100))),
            createdAt: TestData.referenceDate, updatedAt: TestData.referenceDate)

        harness.controller.sync(with: [orphaned, image])
        #expect(harness.controller.annotationCount == 0)
        #expect(Self.annotations(document).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func annotationsMatchStoredRects() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let document = harness.document
        let cross = try Self.highlight(
            id: "cross", selection: Self.crossPageSelection(document), document: document)
        guard case .pdf(let anchor) = cross.anchor else {
            Issue.record("expected a PDF anchor")
            return
        }
        harness.controller.sync(with: [cross])

        for scale in [0.5, 2.0] {
            harness.pdfView.scaleFactor = scale
            let annotations = Self.annotations(document)
            #expect(annotations.count == anchor.pages.count)
            for entry in anchor.pages {
                let page = try #require(document.page(at: entry.pageIndex))
                let onPage = page.annotations.compactMap { $0 as? StudyHighlightAnnotation }
                #expect(onPage.count == 1)
                let expected = PDFHighlightGeometry.bounds(of: entry.rects.map(\.cgRect))
                let actual = try #require(onPage.first?.bounds)
                #expect(actual == expected, "scale \(scale): \(actual) vs \(expected)")
            }
        }
    }

    @Test
    func keysPickColors() {
        #expect(PDFHighlightController.color(forKey: "1", current: .pink) == .yellow)
        #expect(PDFHighlightController.color(forKey: "3", current: .pink) == .blue)
        #expect(PDFHighlightController.color(forKey: "5", current: .pink) == .purple)
        #expect(PDFHighlightController.color(forKey: "h", current: .pink) == .pink)
        #expect(PDFHighlightController.color(forKey: "H", current: .green) == .green)
        #expect(PDFHighlightController.color(forKey: "6", current: .pink) == nil)
        #expect(PDFHighlightController.color(forKey: "0", current: .pink) == nil)
        #expect(PDFHighlightController.color(forKey: "x", current: .pink) == nil)
        #expect(PDFHighlightController.color(forKey: nil, current: .pink) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func topLeftRectMirrorsY() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        let rect = PDFHighlightController.topLeftRect(CGRect(x: 10, y: 100, width: 50, height: 20), in: view)
        #expect(rect == CGRect(x: 10, y: 680, width: 50, height: 20))
    }

    @Test(.timeLimit(.minutes(1)))
    func revealingUnknownHighlightReturnsFalse() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        #expect(harness.controller.reveal(highlightId: "missing") == false)
    }
}
