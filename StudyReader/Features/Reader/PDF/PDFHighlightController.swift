import AppKit
import Foundation
import PDFKit

/// Draws the stored highlights of a PDF as display-only annotations, hit-tests them, and turns selections into new
/// highlights (SPEC F-06, ARCHITECTURE §5.1). The database is the source of truth: annotations are added to and
/// removed from the in-memory pages only, and the document is never written (ADR-0003). PDFKit objects stay on the
/// main actor.
@MainActor
final class PDFHighlightController {
    /// Alpha of a drawn highlight; `HighlightPalette` colors are opaque.
    static let highlightAlpha: CGFloat = 0.5
    private static let flashDuration: Duration = .milliseconds(700)

    private struct Drawn {
        let highlightId: String
        let createdAt: Date
        let color: HighlightColor
        let pages: [PDFAnchor.PageRects]
        var annotations: [(pageIndex: Int, annotation: StudyHighlightAnnotation)]
    }

    private let model: ReaderModel
    private let pdfView: StudyPDFView
    private var drawn: [String: Drawn] = [:]
    private weak var syncedDocument: PDFDocument?
    private var flash: (page: PDFPage, annotation: PDFAnnotation)?
    private var flashTask: Task<Void, Never>?

    /// Number of `StudyHighlightAnnotation`s currently on the pages.
    private(set) var annotationCount = 0

    init(model: ReaderModel, pdfView: StudyPDFView) {
        self.model = model
        self.pdfView = pdfView
        pdfView.onSelectionFinished = { [weak self] selection in self?.selectionFinished(selection) }
        pdfView.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
        pdfView.onClick = { [weak self] event in self?.handleClick(event) ?? false }
    }

    /// The color a highlight annotation is drawn in.
    static func annotationColor(for color: HighlightColor) -> NSColor {
        HighlightPalette.nsColor(color).withAlphaComponent(highlightAlpha)
    }

    // MARK: - Drawing

    /// Diff by highlight id + color: removes annotations of deleted, recolored or re-anchored highlights and adds new
    /// ones (only kind `.text` with a `.pdf` anchor and status `.ok`). Adds in `createdAt` order so newer ones draw
    /// on top; when a highlight has to be re-added, every newer one is re-added after it to keep that order.
    func sync(with highlights: [Highlight]) {
        guard let document = pdfView.document else {
            return
        }
        if syncedDocument !== document {
            // A different document: the old annotations went with the old pages.
            drawn = [:]
            annotationCount = 0
            syncedDocument = document
        }

        let wanted = highlights
            .filter { $0.kind == .text && $0.anchorStatus == .ok && Self.pdfAnchor(of: $0) != nil }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt
                    ? lhs.offset < rhs.offset
                    : lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        let wantedIds = Set(wanted.map(\.id))

        for id in drawn.keys where !wantedIds.contains(id) {
            remove(id, in: document)
        }

        var restacking = false
        for highlight in wanted {
            guard let anchor = Self.pdfAnchor(of: highlight) else { continue }
            if !restacking, let existing = drawn[highlight.id],
               existing.color == highlight.color, existing.pages == anchor.pages {
                continue
            }
            restacking = true
            remove(highlight.id, in: document)
            add(highlight, in: document)
        }
    }

    private static func pdfAnchor(of highlight: Highlight) -> PDFAnchor? {
        if case .pdf(let anchor) = highlight.anchor {
            return anchor
        }
        return nil
    }

    private func add(_ highlight: Highlight, in document: PDFDocument) {
        guard let anchor = Self.pdfAnchor(of: highlight) else { return }
        var annotations: [(pageIndex: Int, annotation: StudyHighlightAnnotation)] = []
        for item in StudyHighlightAnnotation.annotations(
            for: highlight,
            color: Self.annotationColor(for: highlight.color)
        ) {
            guard let page = document.page(at: item.pageIndex) else { continue }
            page.addAnnotation(item.annotation)
            pdfView.annotationsChanged(on: page)
            annotations.append(item)
        }
        annotationCount += annotations.count
        drawn[highlight.id] = Drawn(
            highlightId: highlight.id,
            createdAt: highlight.createdAt,
            color: highlight.color,
            pages: anchor.pages,
            annotations: annotations
        )
    }

    private func remove(_ id: String, in document: PDFDocument) {
        guard let entry = drawn.removeValue(forKey: id) else { return }
        for item in entry.annotations {
            if let page = document.page(at: item.pageIndex) {
                page.removeAnnotation(item.annotation)
                pdfView.annotationsChanged(on: page)
            }
        }
        annotationCount -= entry.annotations.count
    }

    // MARK: - Hit testing

    /// Highlight ids under a page-space point on `pageIndex`, newest (createdAt) first. Tests the per-line rects, so
    /// the gap between two lines of one highlight isn't a hit.
    func highlightIds(at point: CGPoint, onPage pageIndex: Int) -> [String] {
        drawn.values
            .filter { entry in
                entry.pages.contains { page in
                    page.pageIndex == pageIndex && page.rects.contains { $0.cgRect.contains(point) }
                }
            }
            .sorted { lhs, rhs in
                lhs.createdAt == rhs.createdAt ? lhs.highlightId < rhs.highlightId : lhs.createdAt > rhs.createdAt
            }
            .map(\.highlightId)
    }

    // MARK: - New highlights

    /// `NewTextHighlight` for the selection: the `PDFAnchorBuilder` anchor, view `.pdf`, escaped plain text as rich
    /// text, the first page, and `color`. Nil for an empty selection or a document that isn't shown.
    func newHighlight(for selection: PDFSelection, color: HighlightColor) -> NewTextHighlight? {
        guard let document = pdfView.document,
              let result = PDFAnchorBuilder.anchor(for: selection, in: document) else { return nil }
        return NewTextHighlight(
            documentId: model.documentId,
            view: .pdf,
            anchor: .pdf(result.anchor),
            text: result.text,
            richText: RichTextMarkdown.escape(result.text),
            pageIndex: result.firstPageIndex,
            positionKey: result.positionKey,
            color: color
        )
    }

    /// Mouse released after a selection: creates the highlight (auto-highlight) or asks the toolbar (off). After an
    /// auto-highlight the PDF selection is cleared and ⌘Z removes the highlight again.
    private func selectionFinished(_ selection: PDFSelection) {
        let settings = model.session.settings
        guard let new = newHighlight(for: selection, color: settings.currentColor) else { return }
        let anchorRect = Self.anchorRect(for: selection, in: pdfView)
        let isAuto = settings.autoHighlight
        Task { @MainActor [weak self] in
            guard let self else { return }
            await model.selectionFinished(new, anchorRect: anchorRect)
            if isAuto, model.transientMessage == nil {
                pdfView.clearSelection()
                registerAutoHighlightUndo()
            }
        }
    }

    private func registerAutoHighlightUndo() {
        guard let undoManager = pdfView.undoManager else { return }
        undoManager.removeAllActions(withTarget: self)
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                await target.model.undoLastAutoHighlight()
            }
        }
        undoManager.setActionName(String(localized: "Highlight"))
    }

    // MARK: - Keys

    /// The color a key press picks: "1"–"5" are `HighlightColor` raw values 0–4, "h"/"H" the current color. Nil for
    /// other keys.
    static func color(forKey key: String?, current: HighlightColor) -> HighlightColor? {
        guard let key, key.count == 1 else { return nil }
        if key.lowercased() == "h" {
            return current
        }
        guard let digit = Int(key), (1...5).contains(digit) else { return nil }
        return HighlightColor(rawValue: digit - 1)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let blocked: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.isDisjoint(with: blocked),
              let selection = pdfView.currentSelection,
              selection.string?.isEmpty == false,
              let color = Self.color(forKey: event.charactersIgnoringModifiers, current: model.session.settings.currentColor),
              let new = newHighlight(for: selection, color: color) else { return false }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await model.createHighlight(new, isAuto: false) != nil {
                pdfView.clearSelection()
            }
        }
        return true
    }

    // MARK: - Clicks

    private func handleClick(_ event: NSEvent) -> Bool {
        guard let document = pdfView.document else { return false }
        let viewPoint = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: viewPoint, nearest: false) else { return false }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return false }
        let point = pdfView.convert(viewPoint, to: page)
        guard let id = highlightIds(at: point, onPage: pageIndex).first,
              let item = drawn[id]?.annotations.first(where: { $0.pageIndex == pageIndex }) else { return false }
        let rect = Self.topLeftRect(pdfView.convert(item.annotation.bounds, from: page), in: pdfView)
        model.showPopover(highlightId: id, anchorRect: rect)
        return true
    }

    // MARK: - Reveal

    /// Scrolls to the highlight and flashes it. An orphaned or image highlight only brings its page into view.
    /// Returns false when the highlight isn't among `model.highlights` (the caller keeps the location pending).
    @discardableResult
    func reveal(highlightId: String) -> Bool {
        guard let document = pdfView.document,
              let highlight = model.highlights.first(where: { $0.id == highlightId }) else { return false }
        if highlight.kind == .text, highlight.anchorStatus == .ok,
           let entry = drawn[highlightId]?.annotations.first,
           let page = document.page(at: entry.pageIndex),
           let first = Self.pdfAnchor(of: highlight)?.pages.first(where: { $0.pageIndex == entry.pageIndex })?.rects.first {
            pdfView.go(to: first.cgRect, on: page)
            startFlash(on: page, rect: first.cgRect)
            return true
        }
        if let index = highlight.pageIndex ?? Self.firstPageIndex(of: highlight.anchor),
           let page = document.page(at: index) {
            pdfView.go(to: page)
        }
        return true
    }

    private static func firstPageIndex(of anchor: HighlightAnchor) -> Int? {
        switch anchor {
        case .pdf(let anchor): anchor.pages.first?.pageIndex
        case .image(let anchor): anchor.pageIndex
        case .text: nil
        }
    }

    private func startFlash(on page: PDFPage, rect: CGRect) {
        endFlash()
        guard !rect.isEmpty else { return }
        let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemOrange.withAlphaComponent(0.6)
        annotation.shouldPrint = false
        page.addAnnotation(annotation)
        pdfView.annotationsChanged(on: page)
        flash = (page, annotation)
        let sleeper = model.session.environment.sleeper
        flashTask = Task { @MainActor [weak self] in
            try? await sleeper.sleep(for: Self.flashDuration)
            guard !Task.isCancelled else { return }
            self?.endFlash()
        }
    }

    private func endFlash() {
        flashTask?.cancel()
        flashTask = nil
        if let flash {
            flash.page.removeAnnotation(flash.annotation)
            pdfView.annotationsChanged(on: flash.page)
        }
        flash = nil
    }

    // MARK: - Coordinates

    /// The last selected line in `view` coordinates, top-left origin (for the popover and the selection toolbar).
    /// `.zero` for a selection without lines.
    static func anchorRect(for selection: PDFSelection, in view: PDFView) -> CGRect {
        guard let line = selection.selectionsByLine().last,
              let page = line.pages.last else { return .zero }
        return topLeftRect(view.convert(line.bounds(for: page), from: page), in: view)
    }

    /// Converts a rect in `view`'s own coordinates to top-left origin. `PDFView` is not flipped, so y is mirrored.
    static func topLeftRect(_ rect: CGRect, in view: NSView) -> CGRect {
        guard !view.isFlipped else { return rect }
        return CGRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
