import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite struct AppDatabaseErrorTests {
    @Test func wrapMapsResultCodes() {
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_NOTADB), stage: .open) == .damaged(code: 26))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_CORRUPT), stage: .migrate) == .damaged(code: 11))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_CANTOPEN), stage: .open) == .cannotOpen(code: 14))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_ERROR), stage: .migrate) == .migrationFailed(code: 1))
        #expect(AppDatabaseError.wrap(CocoaError(.fileWriteNoPermission), stage: .open) == .cannotOpen(code: -1))
        #expect(AppDatabaseError.wrap(AppDatabaseError.folderUnavailable, stage: .migrate) == .folderUnavailable)
    }

    @Test func damagedFileIsReported() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let junk = Data(String(repeating: "not a database ", count: 69).utf8.prefix(1024))
        try junk.write(to: store.databaseURL)

        let error = #expect(throws: AppDatabaseError.self) {
            _ = try AppDatabase.makeShared(fileStore: store)
        }
        if case .damaged = error {} else { Issue.record("Expected .damaged, got \(String(describing: error))") }
    }

    @Test func corruptPagesAreReported() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let queue = try DatabaseQueue(path: store.databaseURL.path(percentEncoded: false))
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE t (x)")
        }
        try queue.close()

        // Offset 100 is the b-tree header of page 1 (sqlite_master); 512 is the smallest page size.
        let handle = try FileHandle(forUpdating: store.databaseURL)
        try handle.seek(toOffset: 100)
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 412))
        try handle.close()

        let header = try Data(contentsOf: store.databaseURL).prefix(16)
        #expect(header == Data("SQLite format 3\u{0}".utf8))

        let error = #expect(throws: AppDatabaseError.self) {
            _ = try AppDatabase.makeShared(fileStore: store)
        }
        if case .damaged = error {} else { Issue.record("Expected .damaged, got \(String(describing: error))") }
    }

    @Test func configurationThrowsOnDamagedFile() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let junk = Data(String(repeating: "not a database ", count: 69).utf8.prefix(1024))
        try junk.write(to: store.databaseURL)

        let error = #expect(throws: DatabaseError.self) {
            _ = try DatabaseQueue(
                path: store.databaseURL.path(percentEncoded: false),
                configuration: AppDatabase.makeConfiguration()
            )
        }
        #expect(error?.resultCode == .SQLITE_NOTADB)
    }

    @Test func migrationFailureIsReported() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let queue = try DatabaseQueue(path: store.databaseURL.path(percentEncoded: false))
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE category (x)")
        }
        try queue.close()

        let error = #expect(throws: AppDatabaseError.self) {
            _ = try AppDatabase.makeShared(fileStore: store)
        }
        #expect(error == .migrationFailed(code: 1))
    }

    @Test func folderFailureIsReported() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "StudyReaderTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appending(path: "blocker", directoryHint: .notDirectory)
        try Data().write(to: blocker)
        let store = FileStore(rootURL: blocker.appending(path: "StudyReader", directoryHint: .isDirectory))

        #expect(throws: AppDatabaseError.folderUnavailable) {
            _ = try AppDatabase.makeShared(fileStore: store)
        }
    }

    @Test func wrapMapsStorageAndBusyCodes() {
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_FULL), stage: .migrate) == .storageFailure(code: 13))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_FULL), stage: .open) == .storageFailure(code: 13))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_IOERR), stage: .open) == .storageFailure(code: 10))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_IOERR_WRITE), stage: .migrate) == .storageFailure(code: 10))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_BUSY), stage: .open) == .busy(code: 5))
        #expect(AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_LOCKED), stage: .migrate) == .busy(code: 6))
    }

    @Test func newerLibraryIsRefused() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        _ = try AppDatabase.makeShared(fileStore: store)

        let path = store.databaseURL.path(percentEncoded: false)
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v3')")
        }
        try queue.close()

        #expect(throws: AppDatabaseError.newerVersion) {
            _ = try AppDatabase.makeShared(fileStore: store)
        }

        let reopened = try DatabaseQueue(path: path)
        let identifiers = try reopened.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        #expect(identifiers == ["v1", "v2", "v3"])
        try reopened.close()
    }

    @Test func messagesNeverContainSQL() throws {
        let cases: [AppDatabaseError] = [
            .folderUnavailable,
            .cannotOpen(code: 14),
            .damaged(code: 26),
            .migrationFailed(code: 1),
            .newerVersion,
            .storageFailure(code: 13),
            .busy(code: 5),
        ]
        let banned = ["SQL", "CREATE", "while executing", "/"]
        for error in cases {
            let description = try #require(error.errorDescription)
            let suggestion = try #require(error.recoverySuggestion)
            #expect(!description.isEmpty)
            #expect(!suggestion.isEmpty)
            for text in [description, suggestion] {
                for fragment in banned {
                    #expect(!text.contains(fragment))
                }
                #expect(text.rangeOfCharacter(from: .decimalDigits) == nil)
            }
            #expect(error.localizedDescription == description)
        }
    }

    @Test func healthyLibraryStillOpens() async throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let database = try AppDatabase.makeShared(fileStore: store)
        let applied = try await database.reader.read { db in
            try AppDatabase.migrator.appliedMigrations(db)
        }
        #expect(applied == ["v1", "v2"])
    }
}
