import Foundation

/// One entry of a PDF's table of contents, as shown in the outline popover (SPEC F-04).
struct PDFOutlineItem: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    /// 0-based page the entry points to. Nil when the destination can't be resolved.
    var pageIndex: Int?
    /// Nil for leaves, so `OutlineGroup` and `List(children:)` show no disclosure arrow.
    var children: [PDFOutlineItem]?
}
