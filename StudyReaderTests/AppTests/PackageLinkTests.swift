import Testing
import GRDB
import Markdown
import FSRS
@testable import StudyReader

/// Proves that hosted tests can import the app's SPM packages (ADR-0011).
@Suite struct PackageLinkTests {
    @Test func grdbOpensInMemoryDatabase() throws {
        let db = try DatabaseQueue()
        let value = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT 1")
        }
        #expect(value == 1)
    }

    @Test func fts5Available() throws {
        let db = try DatabaseQueue()
        let matches = try db.write { db -> Int? in
            try db.execute(sql: "CREATE VIRTUAL TABLE t USING fts5(x)")
            try db.execute(sql: "INSERT INTO t(x) VALUES ('hello world')")
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM t WHERE t MATCH 'hello'")
        }
        #expect(matches == 1)
    }

    @Test func markdownParses() {
        let document = Document(parsing: "# Title\n\nBody")
        #expect(document.childCount == 2)
    }

    @Test func fsrsRatingsAvailable() {
        #expect(Rating.allCases.contains(.good))
    }
}
