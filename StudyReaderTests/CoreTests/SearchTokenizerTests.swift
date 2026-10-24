import Foundation
import GRDB
@testable import StudyReader
import Testing

@Suite struct SearchTokenizerTests {
    private typealias S = SearchSamples

    // MARK: Normalizer

    @Test func normalizeUnfoldsLigatures() {
        #expect(SearchTokenNormalizer.normalize(S.findLigature) == "find")
        #expect(SearchTokenNormalizer.normalize(S.flowLigature) == "flow")
    }

    @Test func normalizeRemovesSoftHyphen() {
        #expect(SearchTokenNormalizer.normalize(S.photosynthesisSoftHyphen) == S.photosynthesisPlain)
    }

    @Test func normalizeLowercases() {
        #expect(SearchTokenNormalizer.normalize("ATP") == "atp")
        #expect(SearchTokenNormalizer.normalize("\u{FB01}ND") == "find")
    }

    @Test func normalizeComposesButKeepsDiacritics() {
        #expect(SearchTokenNormalizer.normalize(S.resumeDecomposed) == "r\u{00E9}sum\u{00E9}")
    }

    @Test func normalizeKeepsPlainTokens() {
        #expect(SearchTokenNormalizer.normalize("resume") == "resume")
        #expect(SearchTokenNormalizer.normalize(S.photosynthesisPlain) == S.photosynthesisPlain)
        #expect(SearchTokenNormalizer.normalize("42") == "42")
    }

    @Test func normalizeDropsSoftHyphenOnlyTokens() {
        #expect(SearchTokenNormalizer.normalize("\u{00AD}") == "")
        #expect(SearchTokenNormalizer.normalize("\u{00AD}\u{00AD}") == "")
        #expect(SearchTokenNormalizer.normalize("") == "")
    }

    @Test func tokenCharactersListsJoiners() {
        #expect(SearchTokenNormalizer.tokenCharacters.unicodeScalars.map(\.value) == [0x00AD])
    }

    // MARK: FTS behaviour

    private static func makeSampleTable(_ db: Database, rows: [(Int64, String)]) throws {
        try db.execute(sql: "CREATE VIRTUAL TABLE sample_fts USING fts5(body, tokenize='studyreader')")
        for (rowid, body) in rows {
            try db.execute(sql: "INSERT INTO sample_fts(rowid, body) VALUES (?, ?)", arguments: [rowid, body])
        }
    }

    private static func match(_ db: Database, _ query: String) throws -> [Int64] {
        try Int64.fetchAll(
            db,
            sql: "SELECT rowid FROM sample_fts WHERE sample_fts MATCH ? ORDER BY rowid",
            arguments: [query]
        )
    }

    private static func quoted(_ term: String) -> String {
        "\"" + term + "\""
    }

    @Test func softHyphenatedWordMatchesTypedWord() throws {
        let database = try AppDatabase.makeInMemory()
        let results = try database.writer.write { db -> [[Int64]] in
            try Self.makeSampleTable(db, rows: [(1, S.photosynthesisSoftHyphen + " occurs in chloroplasts")])
            return try [
                Self.match(db, Self.quoted(S.photosynthesisPlain)),
                Self.match(db, Self.quoted("PHOTOSYNTHESIS")),
                Self.match(db, Self.quoted(S.photosynthesisSoftHyphen)),
                Self.match(db, Self.quoted("photo")),
            ]
        }
        #expect(results[0] == [1])
        #expect(results[1] == [1])
        #expect(results[2] == [1])
        #expect(results[3] == [])
    }

    @Test func ligatureWordsMatchTypedWords() throws {
        let database = try AppDatabase.makeInMemory()
        let results = try database.writer.write { db -> [[Int64]] in
            try Self.makeSampleTable(db, rows: [(1, S.findLigature + " the " + S.flowLigature)])
            return try [
                Self.match(db, Self.quoted("find")),
                Self.match(db, Self.quoted("FIND")),
                Self.match(db, Self.quoted("flow")),
            ]
        }
        #expect(results == [[1], [1], [1]])
    }

    @Test func prefixQueryIsNormalized() throws {
        let database = try AppDatabase.makeInMemory()
        let result = try database.writer.write { db -> [Int64] in
            try Self.makeSampleTable(db, rows: [(1, S.photosynthesisSoftHyphen)])
            return try Self.match(db, "\"" + S.photosynthesisPrefix + "\"*")
        }
        #expect(result == [1])
    }

    @Test func latinBehaviourUnchanged() throws {
        let database = try AppDatabase.makeInMemory()
        let results = try database.writer.write { db -> [[Int64]] in
            try Self.makeSampleTable(db, rows: [
                (1, "Caf\u{00E9} " + S.resumeDecomposed),
                (2, S.resumeCapitalPrecomposed + " answer"),
            ])
            return try [
                Self.match(db, Self.quoted("cafe")),
                Self.match(db, Self.quoted("CAFE")),
                Self.match(db, Self.quoted("resume")),
                Self.match(db, Self.quoted("RESUME")),
                Self.match(db, "\"answer\"*"),
            ]
        }
        #expect(results[0] == [1])
        #expect(results[1] == [1])
        #expect(results[2] == [1, 2])
        #expect(results[3] == [1, 2])
        #expect(results[4] == [2])
    }

    @Test func snippetShowsOriginalText() throws {
        let database = try AppDatabase.makeInMemory()
        let snippet = try database.writer.write { db -> String? in
            try Self.makeSampleTable(db, rows: [(1, S.findLigature + " " + S.photosynthesisSoftHyphen)])
            return try String.fetchOne(
                db,
                sql: "SELECT snippet(sample_fts, 0, '[', ']', '…', 8) FROM sample_fts WHERE sample_fts MATCH ?",
                arguments: [S.photosynthesisPlain]
            )
        }
        let text = try #require(snippet)
        #expect(text.contains("[" + S.photosynthesisSoftHyphen + "]"))
        #expect(text.contains(S.findLigature))
    }

    @Test func registeredOnPoolReaders() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let database = try AppDatabase.makeShared(fileStore: store)
        try database.writer.write { db in
            try Self.makeSampleTable(db, rows: [(1, S.photosynthesisSoftHyphen)])
        }
        let result = try database.reader.read { db in
            try Self.match(db, Self.quoted(S.photosynthesisPlain))
        }
        #expect(result == [1])
    }

    @Test func existingTablesUnaffected() throws {
        _ = try AppDatabase.makeInMemory()
        try SchemaSnapshot.expectMatchesGolden(migration: "v1")
    }
}
