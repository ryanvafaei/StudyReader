import GRDB
import Synchronization
@testable import StudyReader
import Testing

private typealias F = V1FixtureDatabase
private typealias S = SearchSamples

/// Migration v2 (ADR-0013, ADR-0014): FK indexes, `studyreader` FTS tables, column-filtered triggers.
@Suite struct MigrationV2Tests {
    private static let ftsTables = FTSIntegrity.tables

    private static func quoted(_ term: String) -> String {
        "\"" + term + "\""
    }

    private static func rowids(_ db: Database, table: String, term: String) throws -> [Int64] {
        try Int64.fetchAll(
            db,
            sql: "SELECT rowid FROM \(table) WHERE \(table) MATCH ?",
            arguments: [quoted(term)]
        )
    }

    private static func matchCount(_ db: Database, table: String, term: String) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM \(table) WHERE \(table) MATCH ?",
            arguments: [quoted(term)]
        ) ?? -1
    }

    private static func rowid(_ db: Database, table: String, id: String) throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT rowid FROM \(table) WHERE id = ?", arguments: [id]) ?? -1
    }

    private static func planDetails(_ db: Database, query: String) throws -> String {
        let rows = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query)
        return rows.map { (row: Row) -> String in row["detail"] }.joined(separator: "\n")
    }

    /// Inserts a document with the given title/author, a highlight, a text unit and a note.
    private static func insertSearchable(
        _ db: Database,
        documentId: String,
        highlightId: String,
        title: String,
        author: String,
        highlightText: String,
        unitText: String,
        noteBody: String
    ) throws {
        try TestData.document(id: documentId, title: title, author: author).insert(db)
        try TestData.highlight(documentId: documentId, id: highlightId, text: highlightText).insert(db)
        try db.execute(
            sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, ?)",
            arguments: [documentId, unitText]
        )
        try db.execute(
            sql: "INSERT INTO documentNote (documentId, body, updatedAt) VALUES (?, ?, 1790000000)",
            arguments: [documentId, noteBody]
        )
    }

    // MARK: Schema shape

    @Test func foreignKeyLookupsUseIndexes() throws {
        let db = try AppDatabase.makeInMemory()
        let cases: [(query: String, index: String)] = [
            ("SELECT * FROM reviewLog WHERE cardId = 'x'", "reviewLog_card"),
            ("SELECT * FROM reviewLog WHERE themedReviewId = 'x'", "reviewLog_themedReview"),
            ("SELECT * FROM documentTag WHERE tagId = 'x'", "documentTag_tag"),
            ("SELECT * FROM document WHERE categoryId = 'x'", "document_category"),
        ]
        try db.reader.read { db in
            for testCase in cases {
                let plan = try Self.planDetails(db, query: testCase.query)
                #expect(plan.contains("INDEX \(testCase.index)"), "\(testCase.query) plan: \(plan)")
            }
        }
    }

    @Test func ftsTablesUseSearchTokenizer() throws {
        let db = try AppDatabase.makeInMemory()
        try db.reader.read { db in
            for table in Self.ftsTables {
                let sql = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [table]) ?? ""
                #expect(sql.contains("tokenize='studyreader'"), "\(table) should use studyreader: \(sql)")
            }
            let syncTriggers = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name GLOB '__*'"
            ) ?? -1
            #expect(syncTriggers == 0)
            let triggers = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger'") ?? -1
            #expect(triggers == 12)
        }
    }

    // MARK: Trigger filtering (L5)

    @Test func metadataUpdatesDoNotReindex() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "d0000000-0000-4000-8000-000000000001"
        let highlightId = "h0000000-0000-4000-8000-000000000001"
        try await db.writer.write { db in
            try TestData.document(id: documentId, title: "Alpha").insert(db)
            try TestData.highlight(documentId: documentId, id: highlightId, text: "alpha beta").insert(db)
        }

        let metadataTrace = Mutex<[String]>([])
        try await db.writer.write { db in
            db.trace { event in metadataTrace.withLock { $0.append(event.description) } }
            defer { db.trace() }
            try db.execute(
                sql: "UPDATE document SET progress = 0.5, lastOpenedAt = 1790000999 WHERE id = ?",
                arguments: [documentId]
            )
            try db.execute(
                sql: "UPDATE highlight SET color = 2, anchorStatus = 'orphaned' WHERE id = ?",
                arguments: [highlightId]
            )
        }
        let metadata = metadataTrace.withLock { $0 }
        #expect(!metadata.contains { $0.contains("document_fts_au") || $0.contains("highlight_fts_au") })

        let contentTrace = Mutex<[String]>([])
        try await db.writer.write { db in
            db.trace { event in contentTrace.withLock { $0.append(event.description) } }
            defer { db.trace() }
            try db.execute(sql: "UPDATE document SET title = 'Renamed' WHERE id = ?", arguments: [documentId])
            try db.execute(sql: "UPDATE highlight SET note = 'n' WHERE id = ?", arguments: [highlightId])
        }
        let content = contentTrace.withLock { $0 }
        #expect(content.contains { $0.contains("document_fts_au") })
        #expect(content.contains { $0.contains("highlight_fts_au") })

        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    // MARK: Search on live tables (M3)

    @Test func foldedSearchOnLiveTables() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "d1000000-0000-4000-8000-000000000001"
        try await db.writer.write { db in
            try Self.insertSearchable(
                db,
                documentId: documentId,
                highlightId: "h1000000-0000-4000-8000-000000000001",
                title: S.resumeCapitalPrecomposed,
                author: S.authorWithDiacritics,
                highlightText: S.findLigature + " " + S.photosynthesisSoftHyphen,
                unitText: S.resumeDecomposed,
                noteBody: S.flowLigature
            )
        }

        try await db.reader.read { db in
            let value1 = try Self.matchCount(db, table: "highlight_fts", term: "find")
            #expect(value1 == 1)
            let value2 = try Self.matchCount(db, table: "highlight_fts", term: S.photosynthesisPlain)
            #expect(value2 == 1)
            let value3 = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM highlight_fts WHERE highlight_fts MATCH ?",
                arguments: ["\"" + S.photosynthesisPrefix + "\"*"]
            ) ?? -1
            #expect(value3 == 1)
            let value4 = try Self.matchCount(db, table: "document_fts", term: "nunez")
            #expect(value4 == 1)
            let value5 = try Self.matchCount(db, table: "document_fts", term: "NUNEZ")
            #expect(value5 == 1)
            let value6 = try Self.matchCount(db, table: "document_fts", term: "resume")
            #expect(value6 == 1)
            let value7 = try Self.matchCount(db, table: "documentText_fts", term: "resume")
            #expect(value7 == 1)
            let value8 = try Self.matchCount(db, table: "documentNote_fts", term: "flow")
            #expect(value8 == 1)
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func ftsStaysInSyncThroughWrites() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "d2000000-0000-4000-8000-000000000001"
        let highlightId = "h2000000-0000-4000-8000-000000000001"

        try await db.writer.write { db in
            try Self.insertSearchable(
                db,
                documentId: documentId,
                highlightId: highlightId,
                title: "Alpha",
                author: "Ada",
                highlightText: "alpha beta",
                unitText: "gamma",
                noteBody: "delta"
            )
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
        try await db.reader.read { db in
            let value9 = try Self.matchCount(db, table: "document_fts", term: "alpha")
            #expect(value9 == 1)
            let value10 = try Self.matchCount(db, table: "highlight_fts", term: "beta")
            #expect(value10 == 1)
            let value11 = try Self.matchCount(db, table: "documentText_fts", term: "gamma")
            #expect(value11 == 1)
            let value12 = try Self.matchCount(db, table: "documentNote_fts", term: "delta")
            #expect(value12 == 1)
        }

        // Indexed columns re-index; a non-indexed column leaves the postings alone.
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE document SET title = 'Beta' WHERE id = ?", arguments: [documentId])
            try db.execute(sql: "UPDATE highlight SET note = 'epsilon' WHERE id = ?", arguments: [highlightId])
            try db.execute(sql: "UPDATE highlight SET color = 3 WHERE id = ?", arguments: [highlightId])
            try db.execute(sql: "UPDATE documentText SET text = 'zeta' WHERE documentId = ?", arguments: [documentId])
            try db.execute(sql: "UPDATE documentNote SET body = 'eta' WHERE documentId = ?", arguments: [documentId])
            try FTSIntegrity.check(db)
        }
        try await db.reader.read { db in
            let value13 = try Self.matchCount(db, table: "document_fts", term: "alpha")
            #expect(value13 == 0)
            let value14 = try Self.matchCount(db, table: "document_fts", term: "beta")
            #expect(value14 == 1)
            let value15 = try Self.matchCount(db, table: "highlight_fts", term: "epsilon")
            #expect(value15 == 1)
            let value16 = try Self.matchCount(db, table: "documentText_fts", term: "gamma")
            #expect(value16 == 0)
            let value17 = try Self.matchCount(db, table: "documentText_fts", term: "zeta")
            #expect(value17 == 1)
            let value18 = try Self.matchCount(db, table: "documentNote_fts", term: "delta")
            #expect(value18 == 0)
            let value19 = try Self.matchCount(db, table: "documentNote_fts", term: "eta")
            #expect(value19 == 1)
        }

        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM highlight WHERE id = ?", arguments: [highlightId])
            try FTSIntegrity.check(db)
        }
        try await db.reader.read { db in
            let value20 = try Self.matchCount(db, table: "highlight_fts", term: "epsilon")
            #expect(value20 == 0)
        }

        // Deleting the document cascades to its text unit and note; the FTS rows go with them.
        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM document WHERE id = ?", arguments: [documentId])
            try FTSIntegrity.check(db)
        }
        try await db.reader.read { db in
            let value21 = try Self.matchCount(db, table: "document_fts", term: "beta")
            #expect(value21 == 0)
            let value22 = try Self.matchCount(db, table: "documentText_fts", term: "zeta")
            #expect(value22 == 0)
            let value23 = try Self.matchCount(db, table: "documentNote_fts", term: "eta")
            #expect(value23 == 0)
        }
    }

    // MARK: Upgrade paths

    @Test func upgradesPopulatedV1Database() throws {
        let queue = try F.make()
        let database = try AppDatabase(queue)

        try database.reader.read { db in
            let applied = try AppDatabase.migrator.appliedMigrations(db)
            #expect(applied == ["v1", "v2"])

            for (table, count) in F.expectedRowCounts {
                let actual = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
                #expect(actual == count, "\(table) row count")
            }
            let highlight = try Highlight.fetchOne(db, key: F.highlightMarkdown)
            #expect(highlight?.text == F.markdownHighlightText)

            // Rows that existed before v2 are searchable with the new tokenizer (the 'rebuild' ran).
            let markdownHighlightRowid = try Self.rowid(db, table: "highlight", id: F.highlightMarkdown)
            let value24 = try Self.rowids(db, table: "highlight_fts", term: "find")
            #expect(value24 == [markdownHighlightRowid])
            let value25 = try Self.rowids(db, table: "highlight_fts", term: S.photosynthesisPlain)
            #expect(value25 == [markdownHighlightRowid])
            let latinRowid = try Self.rowid(db, table: "highlight", id: F.highlightLatin)
            let value26 = try Self.rowids(db, table: "highlight_fts", term: "exam")
            #expect(value26 == [latinRowid])
            let value27 = try Self.matchCount(db, table: "documentText_fts", term: S.photosynthesisPlain)
            #expect(value27 == 2)
            let value28 = try Self.matchCount(db, table: "documentText_fts", term: "chloroplasts")
            #expect(value28 == 1)
            let markdownDocumentRowid = try Self.rowid(db, table: "document", id: F.documentMarkdown)
            let value29 = try Self.rowids(db, table: "document_fts", term: "nunez")
            #expect(value29 == [markdownDocumentRowid])
            let value30 = try Self.matchCount(db, table: "documentNote_fts", term: "midterm")
            #expect(value30 == 1)
        }
        try database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func upgradesOnDiskV1Library() async throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try F.makeOnDisk(fileStore: store)

        let database = try AppDatabase.makeShared(fileStore: store)
        let (applied, mode, hits) = try await database.reader.read { db in
            (
                try AppDatabase.migrator.appliedMigrations(db),
                try String.fetchOne(db, sql: "PRAGMA journal_mode"),
                try Self.matchCount(db, table: "highlight_fts", term: "find")
            )
        }
        #expect(applied == ["v1", "v2"])
        #expect(mode == "wal")
        #expect(hits == 1)
    }

    // MARK: Cascades at volume

    @Test func deletingDocumentWithManyLogsCascades() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "d3000000-0000-4000-8000-000000000001"
        let highlightId = "h3000000-0000-4000-8000-000000000001"
        let cardId = "c3000000-0000-4000-8000-000000000001"

        try await db.writer.write { db in
            try TestData.document(id: documentId, title: "Many logs").insert(db)
            try TestData.highlight(documentId: documentId, id: highlightId, text: "logged text").insert(db)
            try db.execute(
                sql: """
                    INSERT INTO reviewCard (id, highlightId, cardType, fsrsCard, dueAt, state, createdAt)
                    VALUES (?, ?, 'passive', '{}', 1790000000, 'new', 1790000000)
                    """,
                arguments: [cardId, highlightId]
            )
            for index in 0..<2_000 {
                try db.execute(
                    sql: """
                        INSERT INTO reviewLog (id, cardId, rating, reviewedAt, sessionKind, fsrsLog)
                        VALUES (?, ?, 3, ?, 'daily', '{}')
                        """,
                    arguments: ["e\(index)-0000-4000-8000-000000000001", cardId, 1_790_000_000 + Double(index)]
                )
            }
        }

        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM document WHERE id = ?", arguments: [documentId])
            try FTSIntegrity.check(db)
        }
        try await db.reader.read { db in
            let value31 = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewLog")
            #expect(value31 == 0)
            let value32 = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewCard")
            #expect(value32 == 0)
            let value33 = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight")
            #expect(value33 == 0)
        }
    }
}
