import GRDB

/// Test-only guard for the external-content FTS5 tables (ADR-0012, ADR-0013).
/// `rank = 1` also compares each index with its content table, so stale postings fail the check.
enum FTSIntegrity {
    static let tables = ["documentText_fts", "highlight_fts", "documentNote_fts", "document_fts"]

    /// Throws `DatabaseError` (SQLITE_CORRUPT_VTAB) on any mismatch. It writes, so call it inside `writer.write`.
    static func check(_ db: Database) throws {
        for table in tables {
            try db.execute(sql: "INSERT INTO \(table)(\(table), rank) VALUES('integrity-check', 1)")
        }
    }
}
