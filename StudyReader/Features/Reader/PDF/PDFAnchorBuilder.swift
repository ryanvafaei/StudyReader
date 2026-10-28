import Foundation
import PDFKit

/// A PDF-view selection turned into a storable anchor (ARCHITECTURE §5.1).
struct PDFSelectionAnchor: Sendable, Equatable {
    var anchor: PDFAnchor
    var firstPageIndex: Int
    var positionKey: Double
    /// `selection.string`, line breaks kept.
    var text: String
}

/// Builds `PDFAnchor`s from `PDFSelection`s. PDFKit objects never leave the main actor; only the `Sendable` result does.
@MainActor
enum PDFAnchorBuilder {
    static let contextLength = 32
    private static let minimumRectSide = 0.5

    /// nil when the selection has no non-whitespace text or no usable line rect.
    /// Pages come in document order; each gets one rect per selected line (page space, line order).
    /// prefix/suffix are taken from the page text around the selection's first/last text range.
    static func anchor(for selection: PDFSelection, in document: PDFDocument) -> PDFSelectionAnchor? {
        let text = selection.string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let lines = selection.selectionsByLine()
        let pages = selection.pages
            .map { (page: $0, index: document.index(for: $0)) }
            .filter { $0.index >= 0 }
            .sorted { $0.index < $1.index }

        var entries: [PDFAnchor.PageRects] = []
        var firstTop: Double?
        for (page, index) in pages {
            let rects = lines
                .filter { line in line.pages.contains { $0 === page } }
                .map { $0.bounds(for: page) }
                .filter { isUsable($0) }
            guard !rects.isEmpty else { continue }
            if entries.isEmpty, let first = rects.first {
                let cropBox = page.bounds(for: .cropBox)
                firstTop = Double(first.maxY - cropBox.minY)
            }
            entries.append(PDFAnchor.PageRects(pageIndex: index, rects: rects.map(CGRectCodable.init)))
        }
        guard let firstEntry = entries.first, let firstTop,
              let firstPage = document.page(at: firstEntry.pageIndex),
              let lastEntry = entries.last,
              let lastPage = document.page(at: lastEntry.pageIndex) else { return nil }

        let prefix = contextBefore(selection, on: firstPage)
        let suffix = contextAfter(selection, on: lastPage)
        let pageHeight = Double(firstPage.bounds(for: .cropBox).height)
        let key = positionKey(pageIndex: firstEntry.pageIndex, pageHeight: pageHeight, topOfFirstRect: firstTop)
        return PDFSelectionAnchor(
            anchor: PDFAnchor(pages: entries, text: text, prefix: prefix, suffix: suffix),
            firstPageIndex: firstEntry.pageIndex,
            positionKey: key,
            text: text
        )
    }

    /// ARCHITECTURE §5.5: `Double(pageIndex) * 1_000_000 + (pageHeight - topOfFirstRect)`.
    nonisolated static func positionKey(pageIndex: Int, pageHeight: Double, topOfFirstRect: Double) -> Double {
        Double(pageIndex) * 1_000_000 + (pageHeight - topOfFirstRect)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > minimumRectSide && rect.height > minimumRectSide
    }

    private static func contextBefore(_ selection: PDFSelection, on page: PDFPage) -> String {
        guard selection.numberOfTextRanges(on: page) > 0, let pageText = page.string else { return "" }
        let range = selection.range(at: 0, on: page)
        let ns = pageText as NSString
        guard range.location != NSNotFound, range.location <= ns.length else { return "" }
        return String(ns.substring(to: range.location).suffix(contextLength))
    }

    private static func contextAfter(_ selection: PDFSelection, on page: PDFPage) -> String {
        let count = selection.numberOfTextRanges(on: page)
        guard count > 0, let pageText = page.string else { return "" }
        let range = selection.range(at: count - 1, on: page)
        let ns = pageText as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { return "" }
        return String(ns.substring(from: NSMaxRange(range)).prefix(contextLength))
    }
}
