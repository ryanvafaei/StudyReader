# T18: `studyreader` FTS5 tokenizer (ligatures, soft hyphens, case, diacritics)

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` M3, part 1 of 2; scope narrowed to English-only, user decision 2026-10-24)
- **Agent:** data-layer
- **Model / effort:** sonnet, high (user decision for this task; pass both on the first call. It already runs as escalated: review it with code-reviewer effort high, and after two rejections stop and ask the user)
- **Depends on:** T17
- **ADRs:** docs/decisions/0014-search-tokenizer-persian-arabic.md (read it in full; despite the file name it is English-only), docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Add the custom FTS5 tokenizer from ADR-0014 and register it on every database connection. After this task, an FTS table created with `tokenize='studyreader'` matches:
- `photosynthesis` against `photo\u{00AD}synthesis` (soft hyphen U+00AD);
- `find` against `ﬁnd` (ligature U+FB01) and `flow` against `ﬂow` (U+FB02);
- `resume` and `RESUME` against `Résumé` (precomposed) and `résumé` (decomposed, NFD).
The real FTS tables switch to this tokenizer in T19 (migration v2). This task doesn't touch the schema. There is no Persian/Arabic folding (ADR-0014).

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
    /// Kept inside tokens by unicode61, then removed by normalize(_:): U+00AD soft hyphen.
    static let joinerScalars: [Unicode.Scalar] = ["\u{00AD}"]

    /// joinerScalars as one String, for the unicode61 `tokenchars` argument.
    static var tokenCharacters: String { get }   // String(String.UnicodeScalarView(joinerScalars))

    /// 1. NFKC (`precomposedStringWithCompatibilityMapping`), which unfolds ligatures (U+FB01 → "fi").
    /// 2. Drop every scalar that is in joinerScalars.
    /// 3. lowercased().
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
Don't add any other normalization step (no whitespace stripping, no diacritic stripping in Swift, no script-specific folding). unicode61 already removes Latin diacritics before `accept` is called.

`AppDatabase.makeConfiguration()` adds, before `return`:
```swift
configuration.prepareDatabase { db in
    db.add(tokenizer: SearchTokenizer.self)
}
```
Every connection gets the tokenizer: the pool writer, pool readers, in-memory queues, and test queues built with `makeConfiguration()`. Don't change anything else in `AppDatabase`.

If Swift 6 strict concurrency complains about the class or the `prepareDatabase` closure, don't add `@unchecked Sendable` or `nonisolated(unsafe)`. Report BLOCKED with the exact diagnostic. If a test below fails because unicode61 itself doesn't behave as described (for example the NFD row), don't change the normalizer to compensate. Report BLOCKED with the actual tokens.

## Tests (`@Suite struct SearchTokenizerTests`, filter `StudyReaderTests/SearchTokenizerTests`)
Use the `SearchSamples` constants from T16 (`S` below). Never type ligatures, soft hyphens or combining marks as literal characters; use the constants or `\u{...}` escapes.

Normalizer unit tests:
- `normalizeUnfoldsLigatures`: `normalize(S.findLigature) == "find"` and `normalize(S.flowLigature) == "flow"`.
- `normalizeRemovesSoftHyphen`: `normalize(S.photosynthesisSoftHyphen) == S.photosynthesisPlain`.
- `normalizeLowercases`: `normalize("ATP") == "atp"` and `normalize("\u{FB01}ND") == "find"` (lowercasing runs after NFKC).
- `normalizeComposesButKeepsDiacritics`: `normalize(S.resumeDecomposed) == "r\u{00E9}sum\u{00E9}"`. Diacritic removal is unicode61's job, not the normalizer's; this pins NFKC composition.
- `normalizeKeepsPlainTokens`: `normalize("resume") == "resume"`, `normalize(S.photosynthesisPlain) == S.photosynthesisPlain`, `normalize("42") == "42"`.
- `normalizeDropsSoftHyphenOnlyTokens`: `normalize("\u{00AD}") == ""`, `normalize("\u{00AD}\u{00AD}") == ""`, `normalize("") == ""`.
- `tokenCharactersListsJoiners`: `SearchTokenNormalizer.tokenCharacters.unicodeScalars.map(\.value) == [0x00AD]`.

FTS behaviour tests use a scratch table in `AppDatabase.makeInMemory()`:
```sql
CREATE VIRTUAL TABLE sample_fts USING fts5(body, tokenize='studyreader')
```
Insert rows with `INSERT INTO sample_fts(rowid, body) VALUES (?, ?)`. Match with `SELECT rowid FROM sample_fts WHERE sample_fts MATCH ? ORDER BY rowid`. Pass the query as an argument wrapped in double quotes (`"\"" + term + "\""`), the same way `SearchQueryParser` will quote words.
- `softHyphenatedWordMatchesTypedWord`: row 1 = `S.photosynthesisSoftHyphen + " occurs in chloroplasts"`. Queries `S.photosynthesisPlain`, `"PHOTOSYNTHESIS"` and `S.photosynthesisSoftHyphen` each return `[1]`. Query `"photo"` returns `[]` (the soft hyphen joins, it doesn't split). This is the M3 failing test.
- `ligatureWordsMatchTypedWords`: row 1 = `S.findLigature + " the " + S.flowLigature`. Queries `"find"`, `"FIND"` and `"flow"` each return `[1]`.
- `prefixQueryIsNormalized`: row 1 = `S.photosynthesisSoftHyphen`. The query string `"\"" + S.photosynthesisPrefix + "\"*"` returns `[1]`.
- `latinBehaviourUnchanged`:
  - row 1 = `"Caf\u{00E9} " + S.resumeDecomposed`;
  - row 2 = `S.resumeCapitalPrecomposed + " answer"`.
  - Queries `cafe` and `CAFE` return `[1]`; `resume` and `RESUME` return `[1, 2]`;
  - query `answer*`, written as `"\"answer\"*"`, returns `[2]`.
- `snippetShowsOriginalText`: row 1 = `S.findLigature + " " + S.photosynthesisSoftHyphen`. `SELECT snippet(sample_fts, 0, '[', ']', '…', 8) FROM sample_fts WHERE sample_fts MATCH ?` with query `S.photosynthesisPlain` returns a string that contains `"[" + S.photosynthesisSoftHyphen + "]"` and contains `S.findLigature` unchanged.
- `registeredOnPoolReaders`: `let store = TestFileStore.make(); defer { TestFileStore.remove(store) }`. Then `let database = try AppDatabase.makeShared(fileStore: store)`. In `database.writer.write`, create `sample_fts` and insert row 1 = `S.photosynthesisSoftHyphen`. Then in `database.reader.read`, a pool reader connection, query `S.photosynthesisPlain` and get `[1]`.
- `existingTablesUnaffected`: after `makeInMemory()`, `SchemaSnapshotTests`' v1 golden still matches. Call `try SchemaSnapshot.expectMatchesGolden(migration: "v1")`, which proves that registering the tokenizer doesn't change the schema.

## Acceptance criteria
1. Ligatures unfold, soft hyphens are removed, tokens are lowercased, and nothing else changes, as ADR-0014 specifies. → tests `SearchTokenizerTests/normalizeUnfoldsLigatures`, `normalizeRemovesSoftHyphen`, `normalizeLowercases`, `normalizeComposesButKeepsDiacritics`, `normalizeKeepsPlainTokens`, `normalizeDropsSoftHyphenOnlyTokens`, `tokenCharactersListsJoiners`
2. In an FTS table using `studyreader`, typed words find soft-hyphenated and ligature text, including prefix queries. → tests `SearchTokenizerTests/softHyphenatedWordMatchesTypedWord`, `ligatureWordsMatchTypedWords`, `prefixQueryIsNormalized`
3. Case-insensitive matching and Latin diacritic folding (precomposed and NFD) still work. → test `SearchTokenizerTests/latinBehaviourUnchanged`
4. Snippets show the original stored text. → test `SearchTokenizerTests/snippetShowsOriginalText`
5. The tokenizer is available on pool reader connections. → test `SearchTokenizerTests/registeredOnPoolReaders`
6. The v1 schema is unchanged. → tests `SearchTokenizerTests/existingTablesUnaffected`, `SchemaSnapshotTests/v1IsFrozen`
7. The full suite passes with no new warnings, and there's no `@unchecked Sendable` or `nonisolated(unsafe)`.

## Out of scope
- Changing the real FTS tables or adding migration `v2` (T19).
- `SearchQueryParser` or `SearchService` (Phase 1). The parser doesn't normalize.
- Any Persian/Arabic folding (ZWNJ, Arabic marks, letter forms). ADR-0014 dropped it deliberately; adding it later needs a new tokenizer version and migration.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
