# T06: GRDB records, part 2: review cards, review log, themed reviews, export targets, embeddings

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T05
- **ADRs:** docs/decisions/0006-fsrs6-scheduling.md, docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Add the remaining record types so every table in schema v1 has a Swift record. Part of epic E0.2. Phase 2 (review-engine) and Phase 1 (export) build on these exact shapes.

Read first: ADR-0012, ARCHITECTURE §4 (tables `reviewCard` … `highlightEmbedding`). Read `StudyRecord.swift`, `Highlight.swift`, `ModelEnums.swift`, `ColumnValues.swift`, and `StudyReaderTests/Support/TestData.swift` (all exist) to follow the same style.

## Files to touch
- `StudyReader/Core/Models/ReviewCard.swift` (new; `ReviewCard` and `ReviewLogEntry`)
- `StudyReader/Core/Models/ThemedReview.swift` (new)
- `StudyReader/Core/Models/ExportTarget.swift` (new)
- `StudyReader/Core/Models/HighlightEmbedding.swift` (new)
- `StudyReaderTests/Support/TestData.swift` (modify: add factories below)
- `StudyReaderTests/CoreTests/ReviewExportRecordTests.swift` (new)

## Interfaces to produce

```swift
struct ReviewCard: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "reviewCard"
    var id: String
    var highlightId: String
    var cardType: CardType
    var clozeRanges: [[Int]]? = nil          // JSON [[start, length]] UTF-16 in display text
    var question: String? = nil
    var answer: String? = nil
    var fsrsCard: String                     // JSON of FSRS.Card; encoded/decoded by review-engine in Phase 2
    var dueAt: Date
    var state: CardState
    var frequencyOverride: ReviewFrequency? = nil
    var suspended: Bool = false
    var suspendedReason: SuspendedReason? = nil
    var introducedAt: Date? = nil
    var createdAt: Date
}

struct ReviewLogEntry: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "reviewLog"
    var id: String
    var cardId: String
    var rating: Int                          // FSRS Rating raw value
    var reviewedAt: Date
    var sessionKind: ReviewSessionKind
    var themedReviewId: String? = nil
    var fsrsLog: String                      // JSON of FSRS.ReviewLog (Phase 2)
}

struct ThemedReview: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "themedReview"
    var id: String
    var name: String
    var filter: ThemedReviewFilter = ThemedReviewFilter()   // JSON
    var cardsPerSession: Int = 20
    var interval: ReviewInterval = .daily                   // JSON
    var orderMode: ReviewOrderMode = .dueFirst
    var lastCompletedAt: Date? = nil
    var createdAt: Date
}

struct ExportTarget: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "exportTarget"
    var id: String
    var title: String
    var scope: ExportScope                                  // JSON
    var options: ExportOptions = ExportOptions()            // JSON
    var googleFileId: String? = nil
    var googleFolderId: String? = nil
    var format: ExportFormat = .markdown
    var keepInSync: Bool = false
    var lastExportedAt: Date? = nil
    var lastStatus: String = "never"         // status values are defined by the export task in Phase 1
    var lastError: String? = nil
    var createdAt: Date
}

struct HighlightEmbedding: StudyRecord, Equatable {
    static let databaseTableName = "highlightEmbedding"
    var highlightId: String
    var modelId: String                      // e.g. "NLEmbedding.sentence.en"
    var dimension: Int
    var vector: Data                         // Float32 little-endian (BLOB)
    var sourceHash: String
}
```
Do not `import FSRS` in these files and don't add FSRS conversion helpers (Phase 2). No associations or query helpers.

```swift
// TestData additions
extension TestData {
    static func reviewCard(
        highlightId: String,
        id: String = UUID().uuidString,
        cardType: CardType = .passive,
        dueAt: Date = referenceDate,
        state: CardState = .new,
        createdAt: Date = referenceDate
    ) -> ReviewCard                          // fsrsCard = "{}"

    static func themedReview(name: String = "Exam week", id: String = UUID().uuidString,
                             createdAt: Date = referenceDate) -> ThemedReview

    static func exportTarget(scope: ExportScope = .all, id: String = UUID().uuidString,
                             createdAt: Date = referenceDate) -> ExportTarget   // title "StudyReader – All highlights"
}
```
Put these in the same `TestData.swift` file (inside `enum TestData` or an extension in that file).

## Acceptance criteria
1. Insert-then-fetch returns an equal value for: a passive `ReviewCard`; a cloze `ReviewCard` with `clozeRanges [[0,4],[10,3]]`, `frequencyOverride .high`, `suspended true`, `suspendedReason .mastery`, `introducedAt` set; a qa card with question/answer. → test `ReviewExportRecordTests/reviewCardRoundTrip`
2. `ReviewLogEntry` round-trips with and without `themedReviewId`; deleting the referenced `ThemedReview` sets `themedReviewId` to NULL (ON DELETE SET NULL). → test `ReviewExportRecordTests/reviewLogRoundTripAndSetNull`
3. `ThemedReview` with `filter` (tagIds, `.all`, colors `[.blue, .pink]`), `interval .weekdays([2, 4])`, `orderMode .random` round-trips; its `filter` column is JSON text. → test `ReviewExportRecordTests/themedReviewRoundTrip`
4. `ExportTarget` with `scope .tag("t1")`, non-default options, google ids, `format .html`, `keepInSync true` round-trips; a default target stores `lastStatus = 'never'`, `format = 'markdown'`, `keepInSync = 0`. → test `ReviewExportRecordTests/exportTargetRoundTrip`
5. `HighlightEmbedding` with a 3-float vector (`([1, 2, 3] as [Float]).withUnsafeBytes { Data($0) }`) round-trips byte-for-byte; `typeof(vector) = 'blob'`. → test `ReviewExportRecordTests/embeddingRoundTrip`
6. `reviewCard.dueAt` and `state` are stored as REAL and TEXT (`'new'`). → test `ReviewExportRecordTests/reviewCardColumnTypes`
7. Deleting the parent highlight removes its review cards, their logs, and its embedding. → test `ReviewExportRecordTests/highlightDeleteCascades`

All tests use `AppDatabase.makeInMemory()` and `TestData`.

## Out of scope
- FSRS scheduling, `FSRS.Card` encoding, session builders (Phase 2). Export rendering/upload (Phase 1). Embedding computation (Phase 3).

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-23, Sonnet (effort medium): APPROVED. Tests 56/56, columns/defaults match §4, cascade and SET NULL verified. Minor: JSON column storage type not asserted in two tests.
