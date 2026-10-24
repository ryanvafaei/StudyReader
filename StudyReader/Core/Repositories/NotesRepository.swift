import Foundation
import GRDB

/// Document notes (SPEC F-09, ARCHITECTURE §4). One `documentNote` row per document, keyed by `documentId`.
/// Saves use the primary-key upsert only (ADR-0012). Highlight notes live on `Highlight.note`
/// and are saved through `HighlightRepository.updateNote(id:note:at:)`.
struct NotesRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    func documentNote(documentId: String) async throws -> DocumentNote? {
        try await writer.read { db in
            try DocumentNote.fetchOne(db, key: documentId)
        }
    }

    /// Creates or replaces the note row for `documentId`. Conflict target is the primary key only.
    func saveDocumentNote(documentId: String, body: String, at date: Date) async throws {
        try await writer.write { db in
            let note = DocumentNote(documentId: documentId, body: body, updatedAt: date)
            _ = try note.upsertAndFetch(db, onConflict: ["documentId"])
        }
    }

    /// Live version of `documentNote(documentId:)`. The first element is the current value; nil when no row exists.
    func observeDocumentNote(documentId: String) -> AsyncValueObservation<DocumentNote?> {
        ValueObservation
            .tracking { db in
                try DocumentNote.fetchOne(db, key: documentId)
            }
            .values(in: writer)
    }
}
