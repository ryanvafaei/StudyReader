import GRDB
@testable import StudyReader
import Testing

@Suite struct V1FixtureDatabaseTests {
    @Test func fixtureHasOnlyV1Applied() throws {
        let queue = try V1FixtureDatabase.make()
        let applied: [String] = try queue.read { db in try AppDatabase.migrator.appliedMigrations(db) }
        #expect(applied == ["v1"])
    }

    @Test func fixtureHasExpectedRowCounts() throws {
        let queue = try V1FixtureDatabase.make()
        for (table, expected) in V1FixtureDatabase.expectedRowCounts {
            let count: Int = try queue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            #expect(count == expected, "row count for \(table)")
        }
    }

    @Test func fixtureRowsDecodeAsRecords() throws {
        let queue = try V1FixtureDatabase.make()
        let counts: [String: Int] = try queue.read { db in
            [
                "category": try DocumentCategory.fetchAll(db).count,
                "document": try LibraryDocument.fetchAll(db).count,
                "documentText": try DocumentText.fetchAll(db).count,
                "highlight": try Highlight.fetchAll(db).count,
                "tag": try LibraryTag.fetchAll(db).count,
                "highlightTag": try HighlightTag.fetchAll(db).count,
                "documentTag": try DocumentTag.fetchAll(db).count,
                "documentNote": try DocumentNote.fetchAll(db).count,
                "reviewCard": try ReviewCard.fetchAll(db).count,
                "themedReview": try ThemedReview.fetchAll(db).count,
                "reviewLog": try ReviewLogEntry.fetchAll(db).count,
                "exportTarget": try ExportTarget.fetchAll(db).count,
                "highlightEmbedding": try HighlightEmbedding.fetchAll(db).count,
            ]
        }
        #expect(counts == V1FixtureDatabase.expectedRowCounts)

        let markdownHighlight: HighlightAnchor? = try queue.read { db in
            try Highlight.fetchOne(db, key: V1FixtureDatabase.highlightMarkdown)?.anchor
        }
        #expect(markdownHighlight == .text(TextAnchor(
            start: 0, length: 19, text: V1FixtureDatabase.markdownHighlightText,
            prefix: "", suffix: "", sourceVersion: 1)))
        #expect(V1FixtureDatabase.markdownHighlightText.utf16.count == 19)
    }

    @Test func onDiskFixtureReopensAtV1() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try V1FixtureDatabase.makeOnDisk(fileStore: store)

        let queue = try DatabaseQueue(
            path: store.databaseURL.path(percentEncoded: false),
            configuration: AppDatabase.makeConfiguration())
        let applied: [String] = try queue.read { db in try AppDatabase.migrator.appliedMigrations(db) }
        let documents: Int = try queue.read { db in try LibraryDocument.fetchCount(db) }
        #expect(applied == ["v1"])
        #expect(documents == 2)
    }
}
