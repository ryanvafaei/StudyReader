---
name: record-types-notes
description: GRDB record types (T05) layout, StudyRecord date strategy requirement form, and capture pitfalls in async write closures
metadata:
  type: reference
---

- Records live in `StudyReader/Core/Models/`: `StudyRecord.swift`, `DocumentCategory.swift`, `LibraryDocument.swift` (also `DocumentText`), `Highlight.swift`, `Tagging.swift` (`LibraryTag`, `HighlightTag`, `DocumentTag`), `DocumentNote.swift`. `TestData` is in `StudyReaderTests/Support/TestData.swift`.
- `StudyRecord` must declare `databaseDateEncodingStrategy(for:)` and `databaseDateDecodingStrategy(for:)` as protocol requirements, with defaults in the extension. An extension-only method is not a GRDB requirement, so GRDB ignores it and dates fall back to the reference date (2001 epoch). GRDB 7.11 declares them on `EncodableRecord` and `FetchableRecord`, as `static func ...(for column: String)`.
- Swift 6 pitfall: `var x` used then captured by `db.writer.write { }` fails with `#SendableClosureCaptures`. Copy to a `let` first (`let updated = edited`), then capture the `let`.
- Selecting several scalars: `try await db.reader.read { db in try (a: String.fetchOne(...), b: Int.fetchOne(...)) }` avoids non-Sendable `Row` returns.
- Test suites: `RecordCodingTests` (3 tests, column storage) and `RecordRoundTripTests` (10 tests, round trips, FTS update, NOCASE tag uniqueness). Run with `-only-testing:StudyReaderTests/RecordCodingTests -only-testing:StudyReaderTests/RecordRoundTripTests`.

## T06 additions
- Records added: `ReviewCard.swift` (`ReviewCard`, `ReviewLogEntry`), `ThemedReview.swift`, `ExportTarget.swift`, `HighlightEmbedding.swift`. Suite: `CoreTests/ReviewExportRecordTests.swift` (7 tests). Full suite now 56 tests.
- Test highlight ids must be valid hex-like UUID strings (use `...0000e1`, not letters outside a-f); not enforced by SQL but keeps fixtures tidy.
- `String.fetchOne(db, sql:)` already returns `String?`; don't write `String?.fetchOne(...) ?? nil`.
- Nested Codable JSON (`[[Int]]?`, `ThemedReviewFilter`, `ExportOptions`) round-trips through GRDB without custom code; `typeof(...)` is 'text'.
