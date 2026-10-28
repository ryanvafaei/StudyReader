import Foundation

/// `exportTarget.lastStatus` values (ADR-0018). No other values are written.
enum ExportStatus: String, Sendable, CaseIterable {
    case never, ok, queued, failed, docMissing, signInRequired
}

/// One highlight prepared for rendering (ARCHITECTURE §9.1).
struct ExportHighlight: Sendable, Equatable {
    var id: String
    var documentId: String
    var kind: HighlightKind
    var color: HighlightColor
    var pageIndex: Int?
    /// editedText → `RichTextMarkdown.escape(editedText)`; else richText if non-empty; else `escape(text)`. "" for images.
    var body: String
    /// Trimmed.
    var note: String
    /// Sorted case-insensitively.
    var tagNames: [String]
    var positionKey: Double
}

struct ExportDocument: Sendable, Equatable {
    var id: String
    var title: String
    var author: String
    var categoryName: String
    /// Trimmed; nil when empty.
    var documentNote: String?
    /// Ordered by positionKey, then id.
    var highlights: [ExportHighlight]
}

struct ExportContent: Sendable, Equatable {
    var scopeName: String
    /// Ordered by title (`localizedStandardCompare`), then id.
    var documents: [ExportDocument]
}
