import AppKit
import Foundation
import Observation
import PDFKit

/// In-document find for the PDF view (SPEC F-12): all matches of the typed text, highlighted, with one current match
/// that is selected and scrolled into view. Also selects the first match of a term on a page when a global search hit
/// is opened. The document is only read; nothing is written to the PDF (ADR-0003). PDFKit objects stay on the main
/// actor.
@MainActor @Observable
final class PDFFindController {
    /// Fill of the matches PDFKit draws for `highlightedSelections`.
    static let matchColor = NSColor.systemYellow.withAlphaComponent(0.5)

    var isVisible = false
    var query = ""
    private(set) var matchCount = 0
    /// 0-based index of the current match; nil while there is none.
    private(set) var currentIndex: Int?
    /// Changes whenever the bar is asked for (⌘F), so a bar that is already open takes the keyboard focus again.
    private(set) var focusRequest = 0

    @ObservationIgnored private let pdfView: StudyPDFView
    @ObservationIgnored private var matches: [PDFSelection] = []

    init(pdfView: StudyPDFView) {
        self.pdfView = pdfView
    }

    // MARK: - Bar

    /// Shows the bar (⌘F, toolbar button). The bar searches a query typed earlier again when it appears.
    func show() {
        isVisible = true
        focusRequest += 1
    }

    /// Hides the bar and clears the highlighted matches. The current selection stays, so it can still be highlighted.
    func close() {
        isVisible = false
        clearMatches()
        pdfView.window?.makeFirstResponder(pdfView)
    }

    // MARK: - Searching

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finds every match of `query` (`document.findString`, case and diacritics ignored), highlights them and selects
    /// the first one at or after the current page. An empty query clears everything.
    func search() {
        guard let document = pdfView.document, !trimmedQuery.isEmpty else {
            clearMatches()
            return
        }
        let found = document.findString(trimmedQuery, withOptions: PlainTextFinder.options)
        for match in found {
            match.color = Self.matchColor
        }
        matches = found
        matchCount = found.count
        pdfView.highlightedSelections = found.isEmpty ? nil : found
        guard !found.isEmpty else {
            currentIndex = nil
            return
        }
        let startPage = pdfView.currentPage.map { document.index(for: $0) } ?? 0
        let first = found.firstIndex { pageIndex(of: $0, in: document) >= startPage } ?? 0
        show(matchAt: first, animate: false)
    }

    /// The next match; wraps from the last to the first.
    func next() {
        guard !matches.isEmpty else { return }
        show(matchAt: ((currentIndex ?? -1) + 1) % matches.count, animate: true)
    }

    /// The previous match; wraps from the first to the last.
    func previous() {
        guard !matches.isEmpty else { return }
        show(matchAt: ((currentIndex ?? 0) - 1 + matches.count) % matches.count, animate: true)
    }

    private func show(matchAt index: Int, animate: Bool) {
        currentIndex = index
        let match = matches[index]
        pdfView.setCurrentSelection(match, animate: animate)
        pdfView.go(to: match)
    }

    private func clearMatches() {
        matches = []
        matchCount = 0
        currentIndex = nil
        pdfView.highlightedSelections = nil
    }

    private func pageIndex(of selection: PDFSelection, in document: PDFDocument) -> Int {
        guard let page = selection.pages.first else { return 0 }
        let index = document.index(for: page)
        return index == NSNotFound ? 0 : index
    }

    // MARK: - Search hits

    /// Selects and scrolls to the first match of `term` on `pageIndex` (case and diacritics ignored; whitespace in the
    /// term also matches a line break). False when the page has no match; the view is left alone then.
    @discardableResult
    func selectFirstMatch(of term: String, onPage pageIndex: Int) -> Bool {
        guard let document = pdfView.document,
              let page = document.page(at: pageIndex),
              let text = page.string as NSString?,
              let range = PlainTextFinder.firstRange(of: term, in: text),
              let selection = page.selection(for: range) else { return false }
        pdfView.setCurrentSelection(selection, animate: false)
        pdfView.go(to: selection)
        return true
    }
}
