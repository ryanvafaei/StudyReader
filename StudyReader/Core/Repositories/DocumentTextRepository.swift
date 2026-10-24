import Foundation
import GRDB

/// Extracted text units of a document (`documentText`, ARCHITECTURE §4). PDFs store one unit per page,
/// Markdown one unit per section. Writes that change the text re-index through the FTS triggers (ADR-0014).
struct DocumentTextRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// One transaction: returns false (writing nothing) if the document row is gone; otherwise deletes its
    /// `documentText` rows, inserts `units`, and sets `extractionStatus` `.done` with `extractionVersion` `version`.
    @discardableResult
    func replaceUnits(_ units: [DocumentText], documentId: String, version: Int) async throws -> Bool {
        let units = units
        return try await writer.write { db in
            guard var document = try LibraryDocument.fetchOne(db, key: documentId) else {
                return false
            }
            try DocumentText
                .filter(Column("documentId") == documentId)
                .deleteAll(db)
            for unit in units {
                try unit.insert(db)
            }
            document.extractionStatus = .done
            document.extractionVersion = version
            try document.update(db, columns: ["extractionStatus", "extractionVersion"])
            return true
        }
    }

    /// Sets `extractionStatus` to `.failed` (column-limited update). Missing row: `RepositoryError.notFound`.
    func markFailed(documentId: String) async throws {
        try await writer.write { db in
            guard var document = try LibraryDocument.fetchOne(db, key: documentId) else {
                throw RepositoryError.notFound
            }
            document.extractionStatus = .failed
            try document.update(db, columns: ["extractionStatus"])
        }
    }

    /// Units of the document in `unitIndex` order.
    func fetchUnits(documentId: String) async throws -> [DocumentText] {
        try await writer.read { db in
            try DocumentText
                .filter(Column("documentId") == documentId)
                .order(Column("unitIndex").asc)
                .fetchAll(db)
        }
    }
}
