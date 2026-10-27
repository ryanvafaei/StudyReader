import Foundation

/// Narrows a search (SPEC F-12). Each set field must match; unset fields don't filter.
/// For highlight and highlight-note hits, `tagId` is a tag on the highlight; for the other hits it is a tag on the document.
struct SearchFilters: Sendable, Equatable {
    var tagId: String? = nil
    var categoryId: String? = nil
    var fileType: FileType? = nil
}

/// A document-level hit: extracted text of one page or section, or the title or author.
struct DocumentHit: Sendable, Equatable, Identifiable {
    enum Field: String, Sendable { case text, titleOrAuthor }

    var documentId: String
    var title: String
    var field: Field
    /// PDF page index or Markdown section index for `.text`; nil for `.titleOrAuthor`.
    var unitIndex: Int?
    /// Match wrapped in `**` `**`.
    var snippet: String
    /// bm25, lower is better.
    var rank: Double
    var id: String { "\(documentId)#\(field.rawValue)#\(unitIndex ?? -1)" }
}

/// A hit in the text (or edited text) of a highlight.
struct HighlightHit: Sendable, Equatable, Identifiable {
    var highlightId: String
    var documentId: String
    var documentTitle: String
    var pageIndex: Int?
    var snippet: String
    var rank: Double
    var id: String { highlightId }
}

/// A hit in a highlight note or a document note.
struct NoteHit: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case highlightNote, documentNote }

    var kind: Kind
    var documentId: String
    var documentTitle: String
    /// Set for `.highlightNote`.
    var highlightId: String?
    var snippet: String
    var rank: Double
    var id: String { "\(kind.rawValue)#\(highlightId ?? documentId)" }
}

/// Search results grouped for display (Documents, Highlights, Notes). Each group is ordered by rank, then id.
struct SearchResults: Sendable, Equatable {
    var documents: [DocumentHit] = []
    var highlights: [HighlightHit] = []
    var notes: [NoteHit] = []

    var isEmpty: Bool { documents.isEmpty && highlights.isEmpty && notes.isEmpty }
}
