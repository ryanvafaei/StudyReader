# T18: `studyreader` FTS5 tokenizer for Persian and Arabic search

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` M3, part 1 of 2)
- **Agent:** data-layer
- **Depends on:** T17
- **ADRs:** docs/decisions/0014-search-tokenizer-persian-arabic.md (read it in full), docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Add the custom FTS5 tokenizer from ADR-0014 and register it on every database connection. After this task, an FTS table created with `tokenize='studyreader'` matches:
- `میخواهم` against `می‌خواهم`;
- `کتاب` against `كتاب`, `كِتَاب`, `ﻛﺘﺎﺏ` and `کتـاب`;
- `علی` against `علي` and `على`.
Latin diacritic folding keeps working. The real FTS tables switch to this tokenizer in T19 (migration v2). This task doesn't touch the schema.

Read first: ADR-0014, and the GRDB sources (read-only, already checked out):
- `build/SourcePackages/checkouts/GRDB.swift/GRDB/FTS/FTS5WrapperTokenizer.swift`;
- `build/SourcePackages/checkouts/GRDB.swift/Documentation/FTS5Tokenizers.md` (sections "Wrapper Tokenizers" and "Using a Custom Tokenizer").

## Files to touch
- `StudyReader/Core/Database/SearchTokenizer.swift` (new)
- `StudyReader/Core/Database/AppDatabase.swift` (modify `makeConfiguration()` only)
- `StudyReaderTests/CoreTests/SearchTokenizerTests.swift` (new)

## Interfaces to produce
`SearchTokenizer.swift` (`import Foundation`, `import GRDB`):
```swift
/// Token normalization for full-text search (ADR-0014). Index text and MATCH queries both pass through it.
/// Changing anything here changes the index format: it needs a new migration that rebuilds all FTS tables.
enum SearchTokenNormalizer {
    /// Kept inside tokens by unicode61, then removed by normalize(_:):
    /// U+00AD soft hyphen, U+0640 tatweel, U+064B…U+065F Arabic marks, U+0670 superscript alef, U+200C ZWNJ.
    static let joinerScalars: [Unicode.Scalar]

    /// joinerScalars as one String, for the unicode61 `tokenchars` argument.
    static var tokenCharacters: String { get }   // String(String.UnicodeScalarView(joinerScalars))

    /// 1. NFKC (`precomposedStringWithCompatibilityMapping`).
    /// 2. Drop every scalar that is in joinerScalars or has `properties.isWhitespace`.
    /// 3. Map U+064A → U+06CC, U+0649 → U+06CC, U+0643 → U+06A9, U+06C0 → U+0647.
    /// 4. lowercased().
    /// Returns "" when nothing is left.
    static func normalize(_ token: String) -> String
}

/// FTS5 tokenizer `studyreader`: unicode61 (remove_diacritics 2, tokenchars = joiners) plus SearchTokenNormalizer.
final class SearchTokenizer: FTS5WrapperTokenizer {
    static let name = "studyreader"
    let wrappedTokenizer: any FTS5Tokenizer

    /// Ignores `arguments`.
    init(db: Database, arguments: [String]) throws {
        wrappedTokenizer = try db.makeTokenizer(Self.baseDescriptor)
    }

    static var baseDescriptor: FTS5TokenizerDescriptor {
        FTS5TokenizerDescriptor(components: [
            "unicode61", "remove_diacritics", "2", "tokenchars", SearchTokenNormalizer.tokenCharacters,
        ])
    }

    func accept(token: String, flags: FTS5TokenFlags, for tokenization: FTS5Tokenization,
                tokenCallback: FTS5WrapperTokenCallback) throws {
        let normalized = SearchTokenNormalizer.normalize(token)
        guard !normalized.isEmpty else { return }
        try tokenCallback(normalized, flags)   // don't catch errors from tokenCallback; pass flags unchanged
    }
}
```
Build `joinerScalars` from the code points in the comment. Use `Unicode.Scalar(UInt32)!` only on these constant literals, or build the range with `(0x064B...0x065F).compactMap(Unicode.Scalar.init)`. Keep them in ascending order.

`AppDatabase.makeConfiguration()` adds, before `return`:
```swift
configuration.prepareDatabase { db in
    db.add(tokenizer: SearchTokenizer.self)
}
```
Every connection gets the tokenizer: the pool writer, pool readers, in-memory queues, and test queues built with `makeConfiguration()`. Don't change anything else in `AppDatabase`.

If Swift 6 strict concurrency complains about the class or the `prepareDatabase` closure, don't add `@unchecked Sendable` or `nonisolated(unsafe)`. Report BLOCKED with the exact diagnostic.

## Tests (`@Suite struct SearchTokenizerTests`, filter `StudyReaderTests/SearchTokenizerTests`)
Use the `ArabicScriptSamples` constants from T16 (`S` below). Never type Arabic-script literals.

Normalizer unit tests:
- `normalizeStripsZWNJ`: `normalize(S.wantWithZWNJ) == S.wantWithoutZWNJ`.
- `normalizeStripsHarakatAndTatweel`: `normalize(S.bookWithHarakat) == S.bookPersian` and `normalize(S.bookWithTatweel) == S.bookPersian`.
- `normalizeFoldsArabicYehAndKaf`:
  - `normalize(S.bookArabicKaf) == S.bookPersian`;
  - `normalize(S.aliArabicYeh) == S.aliPersianYeh`;
  - `normalize(S.aliAlefMaksura) == S.aliPersianYeh`.
- `normalizeMapsPresentationFormsAndLigatures`: `normalize(S.bookPresentationForms) == S.bookPersian` and `normalize("\u{FB01}nd") == "find"`.
- `normalizeKeepsPlainTokens`: `normalize("resume") == "resume"`, `normalize(S.bookPersian) == S.bookPersian`, `normalize("42") == "42"`.
- `normalizeDropsMarkOnlyTokens`: `normalize("\u{200C}") == ""`, `normalize("\u{064E}") == ""`, `normalize("") == ""`.
- `tokenCharactersListsJoiners`: `SearchTokenNormalizer.tokenCharacters.unicodeScalars.map(\.value)` is `[0x00AD, 0x0640] + Array(0x064B...0x065F) + [0x0670, 0x200C]`.

FTS behaviour tests use a scratch table in `AppDatabase.makeInMemory()`:
```sql
CREATE VIRTUAL TABLE sample_fts USING fts5(body, tokenize='studyreader')
```
Insert rows with `INSERT INTO sample_fts(rowid, body) VALUES (?, ?)`. Match with `SELECT rowid FROM sample_fts WHERE sample_fts MATCH ? ORDER BY rowid`. Pass the query as an argument wrapped in double quotes (`"\"" + term + "\""`), the same way `SearchQueryParser` will quote words.
- `persianQueryMatchesArabicFormsAndZWNJ`: row 1 = `S.bookArabicKaf + " " + S.wantWithZWNJ`. Queries `S.bookPersian`, `S.wantWithoutZWNJ` and `S.wantWithZWNJ` each return `[1]`. This is the M3 failing test.
- `variantsAllMatchPersianQuery`: rows 1…4 = `S.bookWithHarakat`, `S.bookPresentationForms`, `S.bookWithTatweel`, `S.bookPersian`. Query `S.bookPersian` returns `[1, 2, 3, 4]`. Query `S.bookArabicKaf` also returns `[1, 2, 3, 4]`.
- `yehVariantsMatch`: rows 1…3 = `S.aliArabicYeh`, `S.aliAlefMaksura`, `S.aliPersianYeh`. Query `S.aliPersianYeh` returns `[1, 2, 3]`.
- `prefixQueryIsNormalized`: row 1 = `S.wantWithZWNJ`. The query string `"\"" + S.wantPrefix + "\"*"` returns `[1]`.
- `latinBehaviourUnchanged`:
  - row 1 = `"Café résumé"`, with `résumé` written as NFD: `"re\u{0301}sume\u{0301}"`;
  - row 2 = `"\u{FB01}nd the answer"`.
  - Queries `cafe`, `CAFE` and `resume` return `[1]`, and `find` returns `[2]`;
  - query `answer*`, written as `"\"answer\"*"`, returns `[2]`.
- `snippetShowsOriginalText`: row 1 = `S.bookArabicKaf + " " + S.wantWithZWNJ`. `SELECT snippet(sample_fts, 0, '[', ']', '…', 8) FROM sample_fts WHERE sample_fts MATCH ?` with query `S.bookPersian` returns a string that contains `"[" + S.bookArabicKaf + "]"` and contains `S.wantWithZWNJ` unchanged.
- `registeredOnPoolReaders`: `let store = TestFileStore.make(); defer { TestFileStore.remove(store) }`. Then `let database = try AppDatabase.makeShared(fileStore: store)`. In `database.writer.write`, create `sample_fts` and insert row 1 = `S.bookArabicKaf`. Then in `database.reader.read`, a pool reader connection, query `S.bookPersian` and get `[1]`.
- `existingTablesUnaffected`: after `makeInMemory()`, `SchemaSnapshotTests`' v1 golden still matches. Call `try SchemaSnapshot.expectMatchesGolden(migration: "v1")`, which proves that registering the tokenizer doesn't change the schema.

## Acceptance criteria
1. ZWNJ, harakat, tatweel, yeh/kaf forms, presentation forms and ligatures normalize as ADR-0014 specifies. → tests `SearchTokenizerTests/normalizeStripsZWNJ`, `normalizeStripsHarakatAndTatweel`, `normalizeFoldsArabicYehAndKaf`, `normalizeMapsPresentationFormsAndLigatures`, `normalizeKeepsPlainTokens`, `normalizeDropsMarkOnlyTokens`, `tokenCharactersListsJoiners`
2. In an FTS table using `studyreader`, Persian-keyboard queries find Arabic-form and ZWNJ text. → tests `SearchTokenizerTests/persianQueryMatchesArabicFormsAndZWNJ`, `variantsAllMatchPersianQuery`, `yehVariantsMatch`, `prefixQueryIsNormalized`
3. Latin search behaviour is unchanged, and the ligature folds. → test `SearchTokenizerTests/latinBehaviourUnchanged`
4. Snippets show the original stored text. → test `SearchTokenizerTests/snippetShowsOriginalText`
5. The tokenizer is available on pool reader connections. → test `SearchTokenizerTests/registeredOnPoolReaders`
6. The v1 schema is unchanged. → tests `SearchTokenizerTests/existingTablesUnaffected`, `SchemaSnapshotTests/v1IsFrozen`
7. The full suite passes with no new warnings, and there's no `@unchecked Sendable` or `nonisolated(unsafe)`.

## Out of scope
- Changing the real FTS tables or adding migration `v2` (T19).
- `SearchQueryParser` or `SearchService` (Phase 1). The parser doesn't normalize.
- Folding alef forms, teh marbuta or digits (ADR-0014 "Not folded").

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
