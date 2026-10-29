import Foundation
import GRDB

/// Launch-time cleanup and re-queueing (SPEC §4 reliability; ADR-0016 crash cleanup).
struct LibraryMaintenance: Sendable {
    private let writer: any DatabaseWriter
    private let fileStore: FileStore

    init(database: AppDatabase, fileStore: FileStore) {
        self.writer = database.writer
        self.fileStore = fileStore
    }

    /// Removes `Documents/<id>/` folders (canonical ids only) that have no `document` row, e.g. left by an import
    /// that was interrupted. Returns the removed ids, sorted. Synchronous: called from the launch factory.
    func removeOrphanFolders() throws -> [String] {
        let folderIds = try fileStore.documentFolderIds()
        let known = try writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT id FROM document"))
        }
        let orphans = folderIds.filter { !known.contains($0) }.sorted()
        for id in orphans {
            try fileStore.deleteDocumentFolder(documentId: id)
        }
        return orphans
    }

    /// Runs the passive-card backfill once per Mac (T129, ADR-0021). Does nothing when `settings.passiveCardBackfillDone`
    /// is set. Otherwise backfills with a passive card due at each highlight's creation (oldest first among new cards),
    /// then sets the flag. On error the flag stays false, so the next launch retries. Returns the number inserted.
    func backfillPassiveCardsOnce(cards: ReviewCardRepository, settings: SettingsStore) async throws -> Int {
        guard !settings.passiveCardBackfillDone else { return 0 }
        let inserted = try await cards.backfillPassiveCards { highlight in
            try ReviewCardFactory.passive(highlightId: highlight.id, now: highlight.createdAt)
        }
        settings.passiveCardBackfillDone = true
        return inserted
    }

    /// Ids with `extractionStatus` 'pending', or 'done' with `extractionVersion` below the current version for their
    /// type. Failed documents are not retried. Sorted by id.
    func documentIdsNeedingExtraction() async throws -> [String] {
        let pdfVersion = PDFTextExtractor.version
        let markdownVersion = MarkdownRenderer.version
        return try await writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM document
                WHERE extractionStatus = ?
                   OR (extractionStatus = ? AND fileType = ? AND extractionVersion < ?)
                   OR (extractionStatus = ? AND fileType = ? AND extractionVersion < ?)
                ORDER BY id
                """,
                arguments: [
                    ExtractionStatus.pending.rawValue,
                    ExtractionStatus.done.rawValue, FileType.pdf.rawValue, pdfVersion,
                    ExtractionStatus.done.rawValue, FileType.markdown.rawValue, markdownVersion,
                ]
            )
        }
    }
}
