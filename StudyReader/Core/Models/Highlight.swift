import Foundation

/// `highlight` table (ARCHITECTURE §4). `anchor` is a JSON column.
struct Highlight: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "highlight"

    var id: String
    var documentId: String
    var kind: HighlightKind
    var view: ReaderViewKind
    var color: HighlightColor = .yellow
    var text: String = ""
    var richText: String = ""
    var editedText: String? = nil
    var note: String = ""
    var pageIndex: Int? = nil
    var positionKey: Double
    var anchor: Anchor
    var anchorStatus: AnchorStatus = .ok
    var imagePath: String? = nil
    var createdAt: Date
    var updatedAt: Date
}
