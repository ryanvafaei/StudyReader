import Foundation
import GRDB

/// Owns the database connection (ADR-0003, ADR-0012).
/// `DatabasePool` (WAL) on disk; `DatabaseQueue` in memory, since a pool can't be in-memory.
struct AppDatabase: Sendable {
    let writer: any DatabaseWriter
    var reader: any DatabaseReader { writer }

    /// Runs `AppDatabase.migrator` on `writer`.
    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Opens the library database at `fileStore.databaseURL` (WAL) and migrates it.
    static func makeShared(fileStore: FileStore) throws -> AppDatabase {
        try fileStore.createRootDirectories()
        let pool = try DatabasePool(
            path: fileStore.databaseURL.path(percentEncoded: false),
            configuration: makeConfiguration()
        )
        return try AppDatabase(pool)
    }

    /// In-memory database for tests, migrated.
    static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "StudyReader"
        return configuration
    }

    /// Append-only. Never edit a registered migration after it ships; add a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try SchemaV1.create(db)
        }
        return migrator
    }
}
