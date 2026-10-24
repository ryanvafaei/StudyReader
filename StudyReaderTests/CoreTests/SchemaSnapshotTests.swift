import GRDB
@testable import StudyReader
import Testing

@Suite struct SchemaSnapshotTests {
    @Test func v1IsFrozen() throws {
        try SchemaSnapshot.expectMatchesGolden(migration: "v1")
    }

    /// Append-only (ADR-0013): later migrations add to the end of this list.
    @Test func registeredMigrationsInOrder() {
        #expect(AppDatabase.migrator.migrations == ["v1"])
    }

    @Test func dumpIsDeterministic() throws {
        let first = try SchemaSnapshot.dumpAfterMigrating(upTo: "v1")
        let second = try SchemaSnapshot.dumpAfterMigrating(upTo: "v1")
        #expect(first == second)
        let lines = first.split(separator: "\n")
        #expect(!lines.contains { $0.hasPrefix("table|grdb_migrations") })
        #expect(!lines.contains { $0.hasPrefix("table|sqlite_") })
        #expect(lines.contains { $0.hasPrefix("table|category|category|CREATE TABLE category (") })
    }
}
