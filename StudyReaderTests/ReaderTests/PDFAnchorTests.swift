import AppKit
import Foundation
import PDFKit
import Testing
@testable import StudyReader

@MainActor
@Suite("PDFAnchor")
struct PDFAnchorTests {
    private func makeDocument() throws -> PDFDocument {
        try #require(PDFDocument(data: PDFFixtureBuilder.plainMultiPage(pageCount: 5)))
    }

    private func pageText(_ document: PDFDocument, _ index: Int) throws -> (page: PDFPage, text: NSString) {
        let page = try #require(document.page(at: index))
        return (page, try #require(page.string) as NSString)
    }

    private func crossPageSelection(_ document: PDFDocument) throws -> PDFSelection {
        let first = try pageText(document, 0)
        let second = try pageText(document, 1)
        let start = first.text.range(of: "line 9")
        let end = second.text.range(of: "line 2")
        try #require(start.location != NSNotFound)
        try #require(end.location != NSNotFound)
        return try #require(document.selection(
            from: first.page, atCharacterIndex: start.location,
            to: second.page, atCharacterIndex: NSMaxRange(end) - 1))
    }

    private func highlight(for anchor: PDFAnchor) -> Highlight {
        Highlight(
            id: "h1", documentId: "d1", kind: .text, view: .pdf, text: anchor.text,
            positionKey: 0, anchor: .pdf(anchor),
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    }

    @Test
    func multiLineAndCrossPage() throws {
        let document = try makeDocument()
        let selection = try crossPageSelection(document)
        let result = try #require(PDFAnchorBuilder.anchor(for: selection, in: document))

        #expect(result.anchor.pages.map(\.pageIndex) == [0, 1])
        #expect(result.anchor.pages[0].rects.count == 2, "page 0 rects: \(result.anchor.pages[0].rects.count)")
        #expect(result.anchor.pages[1].rects.count == 2, "page 1 rects: \(result.anchor.pages[1].rects.count)")
        for entry in result.anchor.pages {
            let page = try #require(document.page(at: entry.pageIndex))
            let cropBox = page.bounds(for: .cropBox)
            for rect in entry.rects {
                #expect(cropBox.contains(rect.cgRect), "rect \(rect) outside \(cropBox)")
            }
        }
        #expect(result.text.contains("line 10"))
        #expect(result.anchor.text == result.text)
        #expect(result.firstPageIndex == 0)
    }

    @Test
    func singleLine() throws {
        let document = try makeDocument()
        let (page, text) = try pageText(document, 2)
        let word = text.range(of: "quick brown")
        try #require(word.location != NSNotFound)
        let selection = try #require(page.selection(for: word))
        let result = try #require(PDFAnchorBuilder.anchor(for: selection, in: document))

        #expect(result.anchor.pages.count == 1)
        #expect(result.anchor.pages[0].pageIndex == 2)
        #expect(result.anchor.pages[0].rects.count == 1)
        #expect(result.firstPageIndex == 2)

        let selected = try #require(selection.string) as NSString
        let located = text.range(of: selected as String)
        let before = text.substring(to: located.location)
        let after = text.substring(from: NSMaxRange(located))
        #expect(!result.anchor.prefix.isEmpty)
        #expect(result.anchor.prefix.count <= PDFAnchorBuilder.contextLength)
        #expect(before.hasSuffix(result.anchor.prefix), "prefix: \(result.anchor.prefix)")
        #expect(after.hasPrefix(result.anchor.suffix), "suffix: \(result.anchor.suffix)")
        #expect(result.anchor.suffix.count == min(PDFAnchorBuilder.contextLength, after.count))
    }

    @Test
    func roundTrip() throws {
        let document = try makeDocument()
        let selection = try crossPageSelection(document)
        let result = try #require(PDFAnchorBuilder.anchor(for: selection, in: document))

        let data = try JSONEncoder().encode(result.anchor)
        let decoded = try JSONDecoder().decode(PDFAnchor.self, from: data)
        #expect(decoded == result.anchor)

        let color = NSColor.yellow.withAlphaComponent(0.35)
        let built = StudyHighlightAnnotation.annotations(for: highlight(for: decoded), color: color)
        let again = StudyHighlightAnnotation.annotations(for: highlight(for: decoded), color: color)
        #expect(built.map(\.pageIndex) == [0, 1])
        #expect(again.map(\.pageIndex) == [0, 1])

        for (index, item) in built.enumerated() {
            let rects = decoded.pages[index].rects.map(\.cgRect)
            let expectedBounds = PDFHighlightGeometry.bounds(of: rects)
            let expectedQuads = PDFHighlightGeometry.quadrilateralPoints(for: rects, relativeTo: expectedBounds.origin)
            let annotation = item.annotation
            #expect(annotation.type?.hasSuffix("Highlight") == true, "type: \(annotation.type ?? "nil")")
            #expect(annotation.highlightId == "h1")
            #expect(annotation.shouldPrint == false)
            expectClose(annotation.bounds, expectedBounds)

            let quads = try #require(annotation.quadrilateralPoints).map(\.pointValue)
            #expect(quads.count == rects.count * 4)
            for (quad, expected) in zip(quads, expectedQuads) {
                #expect(abs(quad.x - expected.x) < 0.001 && abs(quad.y - expected.y) < 0.001,
                        "quad \(quad) vs \(expected)")
            }
            // Offsetting the quads by the bounds origin reproduces each rect's corners.
            for (rectIndex, rect) in rects.enumerated() {
                let corners = expectedQuads[(rectIndex * 4)..<(rectIndex * 4 + 4)].map {
                    CGPoint(x: $0.x + expectedBounds.origin.x, y: $0.y + expectedBounds.origin.y)
                }
                #expect(corners == [
                    CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                ])
            }

            let second = again[index].annotation
            #expect(second.bounds == annotation.bounds)
            #expect(second.quadrilateralPoints?.map(\.pointValue) == annotation.quadrilateralPoints?.map(\.pointValue))
        }
    }

    @Test
    func nonPDFAnchorGivesNoAnnotations() {
        var item = highlight(for: PDFAnchor(pages: [], text: "", prefix: "", suffix: ""))
        item.anchor = .image(ImageAnchor(pageIndex: 0, rect: CGRectCodable(x: 0, y: 0, width: 1, height: 1)))
        #expect(StudyHighlightAnnotation.annotations(for: item, color: .yellow).isEmpty)
    }

    @Test
    func positionKeyOrders() {
        let a = PDFAnchorBuilder.positionKey(pageIndex: 0, pageHeight: 792, topOfFirstRect: 700)
        let b = PDFAnchorBuilder.positionKey(pageIndex: 0, pageHeight: 792, topOfFirstRect: 300)
        let c = PDFAnchorBuilder.positionKey(pageIndex: 1, pageHeight: 792, topOfFirstRect: 700)
        #expect(a < b)
        #expect(b < c)
        #expect(a == 92)
        #expect(c == 1_000_092)
    }

    /// The anchor of the fixture line that starts with `needle` on `page`.
    private func lineAnchor(_ document: PDFDocument, _ page: PDFPage, _ needle: String) throws -> PDFSelectionAnchor {
        let text = try #require(page.string) as NSString
        let found = text.range(of: needle)
        try #require(found.location != NSNotFound, "missing \(needle)")
        let selection = try #require(page.selection(for: found))
        return try #require(PDFAnchorBuilder.anchor(for: selection, in: document))
    }

    @Test
    func anchorsOnARotatedPageStayInsideTheCropBox() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        page.rotation = 90
        let cropBox = page.bounds(for: .cropBox)

        let upper = try lineAnchor(document, page, "Page 1 line 2:")
        let lower = try lineAnchor(document, page, "Page 1 line 8:")
        for result in [upper, lower] {
            #expect(result.anchor.pages.map(\.pageIndex) == [0])
            for rect in result.anchor.pages.flatMap(\.rects) {
                #expect(cropBox.contains(rect.cgRect), "rect \(rect) outside \(cropBox)")
            }
        }
        #expect(upper.positionKey < lower.positionKey, "keys \(upper.positionKey) \(lower.positionKey)")
    }

    @Test
    func anchorsWithAnOffsetCropBox() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        page.setBounds(page.bounds(for: .mediaBox).insetBy(dx: 36, dy: 48), for: .cropBox)
        let cropBox = page.bounds(for: .cropBox)
        try #require(cropBox.minX > 0 && cropBox.minY > 0)

        let upper = try lineAnchor(document, page, "Page 1 line 2:")
        let lower = try lineAnchor(document, page, "Page 1 line 8:")
        for result in [upper, lower] {
            for rect in result.anchor.pages.flatMap(\.rects) {
                #expect(cropBox.contains(rect.cgRect), "rect \(rect) outside \(cropBox)")
            }
            #expect(result.positionKey >= 0 && result.positionKey < 1_000_000, "key \(result.positionKey)")
        }
        #expect(upper.positionKey < lower.positionKey, "keys \(upper.positionKey) \(lower.positionKey)")
    }

    @Test
    func whitespaceSelectionIsNil() throws {
        let document = try makeDocument()
        let (page, text) = try pageText(document, 0)
        let gap = text.range(of: "Page 1 line 1: ")
        try #require(gap.location != NSNotFound)
        let space = NSRange(location: NSMaxRange(gap) - 1, length: 1)
        let selection = try #require(page.selection(for: space))
        #expect(PDFAnchorBuilder.anchor(for: selection, in: document) == nil)
    }

    private func expectClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.001) {
        #expect(abs(lhs.minX - rhs.minX) < tolerance && abs(lhs.minY - rhs.minY) < tolerance
                && abs(lhs.width - rhs.width) < tolerance && abs(lhs.height - rhs.height) < tolerance,
                "bounds \(lhs) vs \(rhs)")
    }
}
