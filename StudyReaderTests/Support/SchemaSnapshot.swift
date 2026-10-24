import Foundation
import GRDB
@testable import StudyReader
import Testing

enum SchemaSnapshotError: Error { case missingGolden(String) }

enum SchemaSnapshot {
    /// One line per schema object, sorted by type then name:
    /// "<type>|<name>|<tbl_name>|<sql with every whitespace run collapsed to one space>".
    /// Query: SELECT type, name, tbl_name, sql FROM sqlite_master
    ///        WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT GLOB 'grdb_*'
    ///        ORDER BY type, name
    /// Collapse with sql.split(whereSeparator: \.isWhitespace).joined(separator: " ").
    /// Lines joined with "\n", plus one trailing "\n".
    static func dump(_ db: Database) throws -> String {
        let lines: [String] = try Row.fetchAll(db, sql: """
            SELECT type, name, tbl_name, sql FROM sqlite_master
            WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT GLOB 'grdb_*'
            ORDER BY type, name
            """).map { row in
                let type: String = row["type"]
                let name: String = row["name"]
                let tableName: String = row["tbl_name"]
                let sql: String = row["sql"]
                let collapsed = sql.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                return "\(type)|\(name)|\(tableName)|\(collapsed)"
            }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Fresh DatabaseQueue(configuration: AppDatabase.makeConfiguration()), then
    /// AppDatabase.migrator.migrate(queue, upTo: migration), then dump.
    static func dumpAfterMigrating(upTo migration: String) throws -> String {
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: migration)
        return try queue.read { db in try dump(db) }
    }

    /// Bundle(for: BundleToken.self).url(forResource: name, withExtension: "sql", subdirectory: "Fixtures/schema"),
    /// read as UTF-8. Throws .missingGolden(name) if absent.
    static func golden(_ name: String) throws -> String {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: name, withExtension: "sql", subdirectory: "Fixtures/schema"
        ) else {
            throw SchemaSnapshotError.missingGolden(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes text to FileManager.default.temporaryDirectory/StudyReaderSchema/<name>.actual.sql
    /// (creating the folder) and returns its URL, or nil if writing fails.
    static func writeActual(_ text: String, name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "StudyReaderSchema", directoryHint: .isDirectory
        )
        let url = folder.appending(path: "\(name).actual.sql", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Compares dumpAfterMigrating(upTo: migration) with golden(migration). On any difference (or a missing golden)
    /// calls writeActual and records ONE issue:
    /// "Schema <migration> differs from Fixtures/schema/<migration>.sql. Actual dump: <path>. If you edited a
    ///  committed migration, revert the edit (ADR-0013); never regenerate a committed golden."
    static func expectMatchesGolden(migration: String) throws {
        let actual = try dumpAfterMigrating(upTo: migration)
        let expected = try? golden(migration)
        guard actual != expected else { return }
        let path = writeActual(actual, name: migration)?.path(percentEncoded: false) ?? "(could not write actual dump)"
        Issue.record("""
            Schema \(migration) differs from Fixtures/schema/\(migration).sql. Actual dump: \(path). \
            If you edited a committed migration, revert the edit (ADR-0013); never regenerate a committed golden.
            """)
    }

    private final class BundleToken {}
}
