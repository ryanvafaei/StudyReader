import AppKit
import Foundation

/// Draws the stored highlights of a text document as rects under the text (`TextReaderView.drawBackground`; the text
/// storage, and so every UTF-16 offset, stays untouched), hit-tests them, turns selections into new highlights and
/// re-anchors stored ones when the rendering changed (SPEC F-06/F-07, ARCHITECTURE §5.2-§5.3, ADR-0004/0005). The
/// Markdown reader uses it today; the PDF text view reuses it in Phase 3.
@MainActor
final class TextHighlightController {
    /// Alpha of a drawn highlight; `HighlightPalette` colors are opaque.
    static let highlightAlpha: CGFloat = 0.35

    private struct Drawn {
        let id: String
        let range: NSRange
    }

    private let model: ReaderModel
    private let textController: TextReaderController
    private var renderedString: String?
    private var sourceMap = MarkdownSourceMap(entries: [])
    /// What `sync` drew, oldest first (so the last entry is the newest and wins a hit).
    private var drawn: [Drawn] = []

    init(model: ReaderModel, textController: TextReaderController) {
        self.model = model
        self.textController = textController
        let textView = textController.textView
        textView.onSelectionFinished = { [weak self] range in self?.selectionFinished(range) }
        textView.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
        textView.onClick = { [weak self] index, _ in self?.handleClick(atCharacterIndex: index) ?? false }
    }

    /// The rendered string and source map of the current document; call after the text was loaded.
    func setRendered(string: String, sourceMap: MarkdownSourceMap) {
        renderedString = string
        self.sourceMap = sourceMap
    }

    /// The color a highlight is drawn in.
    static func backgroundColor(for color: HighlightColor) -> NSColor {
        HighlightPalette.nsColor(color).withAlphaComponent(highlightAlpha)
    }

    // MARK: - Drawing

    /// Replaces what the last call painted with every `.ok` text highlight with a `.text` anchor inside the text in
    /// `createdAt` order (ties keep the given order), so the newest is painted last and shows on top. The text view
    /// draws the rects under the text (`TextReaderView.drawBackground`).
    func sync(with highlights: [Highlight]) {
        let length = textController.textLength
        let wanted = highlights
            .enumerated()
            .filter { $0.element.kind == .text && $0.element.anchorStatus == .ok }
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt
                    ? lhs.offset < rhs.offset
                    : lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        var entries: [Drawn] = []
        var paints: [TextReaderView.HighlightPaint] = []
        for highlight in wanted {
            guard let range = Self.range(of: highlight), range.length > 0, NSMaxRange(range) <= length else { continue }
            entries.append(Drawn(id: highlight.id, range: range))
            paints.append(.init(range: range, color: Self.backgroundColor(for: highlight.color)))
        }
        drawn = entries
        textController.textView.highlightPaints = paints
    }

    private static func range(of highlight: Highlight) -> NSRange? {
        guard case .text(let anchor) = highlight.anchor, anchor.start >= 0, anchor.length >= 0 else { return nil }
        return NSRange(location: anchor.start, length: anchor.length)
    }

    // MARK: - Hit testing

    /// Ids of the drawn highlights containing the UTF-16 index, newest first.
    func highlightIds(atCharacterIndex index: Int) -> [String] {
        drawn.reversed().filter { NSLocationInRange(index, $0.range) }.map(\.id)
    }

    private func handleClick(atCharacterIndex index: Int) -> Bool {
        guard let id = highlightIds(atCharacterIndex: index).first,
              let entry = drawn.first(where: { $0.id == id }) else { return false }
        model.showPopover(highlightId: id, anchorRect: textController.anchorRect(for: entry.range))
        return true
    }

    // MARK: - New highlights

    /// `NewTextHighlight` for `range` of the rendered string: the `TextAnchoring` anchor, view `.markdown`, F-07 rich
    /// text, the plain substring, no page, position key = start. Nil for an empty or whitespace-only range, a range
    /// outside the text, or before `setRendered`.
    func newHighlight(for range: NSRange, color: HighlightColor) -> NewTextHighlight? {
        guard let string = renderedString, range.location >= 0, range.length > 0,
              NSMaxRange(range) <= (string as NSString).length else { return nil }
        let anchor = TextAnchoring.anchor(for: range, in: string, sourceVersion: MarkdownRenderer.version)
        guard !anchor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return NewTextHighlight(
            documentId: model.documentId,
            view: .markdown,
            anchor: .text(anchor),
            text: anchor.text,
            richText: RichTextMarkdown.markdown(for: range, in: string, sourceMap: sourceMap),
            pageIndex: nil,
            positionKey: TextAnchoring.positionKey(for: anchor),
            color: color
        )
    }

    /// Mouse released after a selection: creates the highlight (auto-highlight) or asks the toolbar (off). After an
    /// auto-highlight the selection collapses and ⌘Z removes the highlight again.
    private func selectionFinished(_ range: NSRange) {
        let settings = model.session.settings
        guard let new = newHighlight(for: range, color: settings.currentColor) else { return }
        let anchorRect = textController.anchorRect(for: range)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await model.selectionFinished(new, anchorRect: anchorRect) != nil {
                collapseSelection(ifStill: range)
                registerAutoHighlightUndo()
            }
        }
    }

    /// Puts the caret after `range`, unless the user has selected something else in the meantime.
    private func collapseSelection(ifStill range: NSRange) {
        let textView = textController.textView
        guard textView.selectedRange() == range else { return }
        textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
    }

    private func registerAutoHighlightUndo() {
        guard let undoManager else { return }
        undoManager.removeAllActions(withTarget: self)
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                await target.model.undoLastAutoHighlight()
            }
        }
        undoManager.setActionName(String(localized: "Highlight"))
    }

    /// The text view's undo manager, else its window's.
    private var undoManager: UndoManager? {
        textController.textView.undoManager ?? textController.textView.window?.undoManager
    }

    /// Drops the undo action this controller registered; called when the tab goes away.
    func tearDown() {
        undoManager?.removeAllActions(withTarget: self)
    }

    // MARK: - Keys

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let blocked: NSEvent.ModifierFlags = [.command, .control, .option]
        let textView = textController.textView
        let selection = textView.selectedRange()
        guard event.modifierFlags.isDisjoint(with: blocked), selection.length > 0,
              let color = HighlightKeys.color(
                  forKey: event.charactersIgnoringModifiers,
                  current: model.session.settings.currentColor
              ),
              let new = newHighlight(for: selection, color: color) else { return false }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // isAuto only makes the highlight the one ⌘Z removes (Edit > Undo Highlight).
            if await model.createHighlight(new, isAuto: true) != nil {
                collapseSelection(ifStill: selection)
                registerAutoHighlightUndo()
            }
        }
        return true
    }

    // MARK: - Re-anchoring

    /// Re-finds every `.text` highlight in the rendered string (ARCHITECTURE §5.3) and stores the result: a moved
    /// anchor (new range, current version) as `.ok`, a lost one as `.orphaned`; an orphan that is found again is `.ok`
    /// again. Returns the number of rows changed. Does nothing before `setRendered`.
    func reanchorAll(_ highlights: [Highlight]) async -> Int {
        guard let string = renderedString else { return 0 }
        let environment = model.session.environment
        let repository = environment.highlightRepository
        let date = environment.now()
        var changed = 0
        var resolver = TextAnchoring.Resolver(text: string)
        for highlight in highlights where highlight.kind == .text {
            guard case .text(let anchor) = highlight.anchor else { continue }
            let update: (anchor: HighlightAnchor, positionKey: Double, status: AnchorStatus)
            switch resolver.resolve(anchor, currentVersion: MarkdownRenderer.version) {
            case .unchanged:
                guard highlight.anchorStatus == .orphaned else { continue }
                update = (highlight.anchor, highlight.positionKey, .ok)
            case .moved(let moved):
                update = (.text(moved), TextAnchoring.positionKey(for: moved), .ok)
            case .orphaned:
                guard highlight.anchorStatus == .ok else { continue }
                update = (highlight.anchor, highlight.positionKey, .orphaned)
            }
            do {
                try await repository.updateAnchor(
                    id: highlight.id,
                    anchor: update.anchor,
                    positionKey: update.positionKey,
                    status: update.status,
                    at: date
                )
                changed += 1
            } catch {
                Log.database.error("Re-anchoring a highlight failed.")
            }
        }
        return changed
    }

    // MARK: - Reveal

    /// Draws the current highlights first (so a location applied before the first draw still finds them), then
    /// selects the highlight's range and scrolls to it if it isn't visible. An orphaned highlight does nothing.
    /// Returns false when the highlight isn't among `model.highlights` (the caller keeps the location pending).
    @discardableResult
    func reveal(highlightId: String) -> Bool {
        guard let highlight = model.highlights.first(where: { $0.id == highlightId }) else { return false }
        sync(with: model.highlights)
        guard highlight.kind == .text, highlight.anchorStatus == .ok,
              let entry = drawn.first(where: { $0.id == highlightId }) else { return true }
        textController.select(entry.range)
        let visible = textController.scrollView.bounds
        let rect = textController.anchorRect(for: entry.range)
        if rect.minY < visible.minY || rect.maxY > visible.maxY {
            textController.scroll(toOffset: entry.range.location)
        }
        return true
    }
}
