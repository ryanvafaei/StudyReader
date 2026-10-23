import Foundation

/// `documentNote` table (ARCHITECTURE §4). One row per document; keyed by `documentId`.
struct DocumentNote: StudyRecord, Equatable {
    static let databaseTableName = "documentNote"

    var documentId: String
    var body: String = ""
    var updatedAt: Date
}
