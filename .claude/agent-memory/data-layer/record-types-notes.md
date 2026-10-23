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
