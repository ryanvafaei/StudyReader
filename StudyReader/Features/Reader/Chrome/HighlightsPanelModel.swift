import AppKit
import Foundation
import Observation

/// One listed highlight with its tag names.
struct PanelHighlightRow: Identifiable, Equatable {
    let highlight: Highlight
    let tagNames: [String]
    var id: String { highlight.id }
    /// "PDF" for view `.pdf`, "Text" for `.text` and `.markdown`; nil when the document is Markdown.
    var viewLabel: String?
    var isOrphaned: Bool { highlight.anchorStatus == .orphaned }
}

struct PanelSection: Identifiable, Equatable {
    /// "PDF view" / "Text view" for PDF documents with both kinds; nil otherwise.
    let title: String?
    let rows: [PanelHighlightRow]
    var id: String { title ?? "all" }
}

/// State behind the Highlights tab (SPEC F-06): the document's highlights in reading order (ARCHITECTURE §5.5),
/// grouped by view for PDF documents.
@MainActor @Observable
final class HighlightsPanelModel {
    private(set) var sections: [PanelSection] = []
    /// Snapshot thumbnails by relative image path, loaded once so the views never read files while drawing.
    private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var errorMessage: String?

    @ObservationIgnored private var tagNames: [String: [String]] = [:]
    @ObservationIgnored private let model: ReaderModel

    init(model: ReaderModel) {
        self.model = model
    }

    var isEmpty: Bool { sections.allSatisfy { $0.rows.isEmpty } }

    /// Follows the document's tag names per highlight until the calling task is cancelled, so tag changes show at
    /// once without a query per row.
    func observeTagNames() async {
        let tags = model.session.environment.tagRepository
        do {
            for try await names in tags.observeTagNamesByHighlight(inDocument: model.documentId) {
                tagNames = names
                errorMessage = nil
                rebuildSections()
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(localized: "Some tags couldn't be loaded.")
        }
    }

    /// Rebuilds the sections from the reader's live highlights and the stored tag names.
    func refresh() async {
        await loadThumbnails(for: model.highlights)
        guard !Task.isCancelled else { return }
        rebuildSections()
    }

    private func rebuildSections() {
        guard let fileType = model.document?.fileType else {
            sections = []
            return
        }
        sections = Self.sections(for: model.highlights, tagNames: tagNames, fileType: fileType)
    }

    func select(_ highlightId: String) {
        model.navigate(to: .highlight(highlightId))
    }

    func delete(_ highlightId: String) async {
        do {
            try await model.session.environment.highlightService.delete(id: highlightId)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The highlight couldn't be deleted.")
        }
    }

    private func loadThumbnails(for highlights: [Highlight]) async {
        let fileStore = model.session.environment.fileStore
        let paths = Set(highlights.compactMap(\.imagePath))
        var loaded: [String: NSImage] = [:]
        for path in paths {
            if let existing = thumbnails[path] {
                loaded[path] = existing
                continue
            }
            guard let url = fileStore.url(forRelativePath: path) else { continue }
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            if let data, let image = NSImage(data: data) {
                loaded[path] = image
            }
        }
        thumbnails = loaded
    }

    nonisolated static func sections(
        for highlights: [Highlight],
        tagNames: [String: [String]],
        fileType: FileType
    ) -> [PanelSection] {
        func ordered(_ items: [Highlight]) -> [Highlight] {
            items.sorted { lhs, rhs in
                lhs.positionKey != rhs.positionKey ? lhs.positionKey < rhs.positionKey : lhs.createdAt < rhs.createdAt
            }
        }
        func rows(_ items: [Highlight]) -> [PanelHighlightRow] {
            ordered(items).map { highlight in
                PanelHighlightRow(
                    highlight: highlight,
                    tagNames: tagNames[highlight.id] ?? [],
                    viewLabel: fileType == .pdf ? (highlight.view == .pdf ? String(localized: "PDF") : String(localized: "Text")) : nil
                )
            }
        }
        guard fileType == .pdf else {
            return highlights.isEmpty ? [] : [PanelSection(title: nil, rows: rows(highlights))]
        }
        let pdfView = highlights.filter { $0.view == .pdf }
        let textView = highlights.filter { $0.view != .pdf }
        switch (pdfView.isEmpty, textView.isEmpty) {
        case (true, true):
            return []
        case (false, true):
            return [PanelSection(title: nil, rows: rows(pdfView))]
        case (true, false):
            return [PanelSection(title: nil, rows: rows(textView))]
        case (false, false):
            return [
                PanelSection(title: String(localized: "PDF view"), rows: rows(pdfView)),
                PanelSection(title: String(localized: "Text view"), rows: rows(textView))
            ]
        }
    }
}
