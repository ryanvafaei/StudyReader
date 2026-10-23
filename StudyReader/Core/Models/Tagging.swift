import Foundation

/// `tag` table (ARCHITECTURE §4). Names are unique case-insensitively at the DB level.
struct LibraryTag: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "tag"

    var id: String
    var name: String
    var createdAt: Date
}

/// `highlightTag` join table.
struct HighlightTag: StudyRecord, Equatable {
    static let databaseTableName = "highlightTag"

    var highlightId: String
    var tagId: String
}

/// `documentTag` join table.
struct DocumentTag: StudyRecord, Equatable {
    static let databaseTableName = "documentTag"

    var documentId: String
    var tagId: String
}
