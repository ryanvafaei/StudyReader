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
        do {
            try fileStore.createRootDirectories()
        } catch {
            Log.database.error("Library folder unavailable")
            throw AppDatabaseError.folderUnavailable
        }
        let pool: DatabasePool
        do {
            pool = try DatabasePool(
                path: fileStore.databaseURL.path(percentEncoded: false),
                configuration: makeConfiguration()
            )
        } catch {
            throw logged(AppDatabaseError.wrap(error, stage: .open), stage: .open)
        }
        do {
            return try AppDatabase(pool)
        } catch {
            throw logged(AppDatabaseError.wrap(error, stage: .migrate), stage: .migrate)
        }
    }

    /// Logs only the stage, the error case and its SQLite code. Never the description, path, or SQL.
    private static func logged(_ error: AppDatabaseError, stage: AppDatabaseError.Stage) -> AppDatabaseError {
        Log.database.error("Library open failed: stage=\(stage.rawValue, privacy: .public) case=\(String(describing: error), privacy: .public)")
        return error
    }

    /// In-memory database for tests, migrated.
    static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "StudyReader"
        configuration.prepareDatabase { db in
            // Read the schema first, so a damaged file throws SQLITE_NOTADB/SQLITE_CORRUPT here.
            // db.add(tokenizer:) can't throw: GRDB calls fatalError if `SELECT fts5(?)` fails to prepare (T22).
            _ = try Row.fetchOne(db, sql: "SELECT * FROM sqlite_master LIMIT 1")
            db.add(tokenizer: SearchTokenizer.self)
        }
        return configuration
    }

    /// Append-only. Never edit a registered migration after it ships; add a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try SchemaV1.create(db)
        }
        migrator.registerMigration("v2") { db in
            try SchemaV2.migrate(db)
        }
        return migrator
    }
}
