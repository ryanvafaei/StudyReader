# T26: Bind dates in queries as Unix seconds

- **Phase:** 0 (fix from second bug hunt `docs/bugs/phase-0-second-pass.md` M1, plus the `DateStorageTests` part of L7)
- **Agent:** data-layer
- **Depends on:** T25
- **ADRs:** docs/decisions/0012-data-layer-conventions.md ("Dates" and "Dates in SQL" bullets)
- **Visual check needed:** no

## Goal
Records store dates as REAL Unix seconds, but only because `StudyRecord`'s encoding strategy runs when a *record* is encoded. A bare `Date` used in a query (`ReviewCard.filter(Column("dueAt") <= now)`) goes through GRDB's `Date.databaseValue`, which binds the TEXT `"yyyy-MM-dd HH:mm:ss.SSS"`. SQLite sorts every REAL before every TEXT, so `dueAt <= now` matches every row, `dueAt > now` matches none, and nothing throws. Add one helper, `Date.databaseUnixSeconds`, that every query uses. Add guard tests: one shows the helper gives correct results, and one pins the raw-`Date` hazard. There's no schema change and no migration.

Also (amended 2026-10-24, user decision): close the `DateStorageTests` part of second-pass finding L7. The existing test `recordRoundTripIsExact` inserts a document and a highlight (FTS-indexed tables) but doesn't end with `FTSIntegrity.check`, which ARCHITECTURE §15 requires. Add that one call. The other suites named in L7 (`UpsertConventionTests`, `ReviewExportRecordTests`, `RecordCodingTests`) stay in `docs/bugs/backlog.md`; don't touch them.

## Files to touch
- `StudyReader/Core/Models/StudyRecord.swift` (modify: add one property to the existing `extension Date`)
- `StudyReaderTests/CoreTests/DateStorageTests.swift` (modify: add four tests and one private helper; add one line to the existing `recordRoundTripIsExact` (see "Change to an existing test"); keep the other four existing tests unchanged)

Read these too, but don't change them: `StudyReaderTests/Support/TestData.swift` (`referenceDate`, `document`, `highlight`, `reviewCard`) and `StudyReaderTests/Support/FTSIntegrity.swift`.

## Interfaces to produce
Add this to the existing `extension Date` in `StudyRecord.swift`, directly below `storageRounded`. Don't create a new file or a second extension:
```swift
    /// The value to bind wherever a date appears in SQL: `filter` expressions, `SQL` interpolation,
    /// `arguments:` and `updateAll` assignments (ADR-0012). It's the same `Double` the `StudyRecord`
    /// encoder writes for this date. Never bind a bare `Date`: GRDB binds it as TEXT, and in SQLite
    /// every REAL sorts before every TEXT, so `dueAt <= date` would match every row.
    /// Example: `ReviewCard.filter(Column("dueAt") <= now.databaseUnixSeconds)`.
    var databaseUnixSeconds: Double {
        timeIntervalSince1970
    }
```
Rules:
- The type is `Double`, not `DatabaseValue` or `SQLExpression`. `Double` is already `SQLExpressible` and `DatabaseValueConvertible` in GRDB 7.11, so it works in `Column(...) <= x`, in `SQL("... \(x)")`, in `arguments: [x]` and in `Column(...).set(to: x)`.
- Don't round. The helper must return exactly `timeIntervalSince1970`, which is what `DatabaseDateEncodingStrategy.timeIntervalSince1970` writes. Rounding happens at write time with `.storageRounded` (ADR-0012), not here.
- Don't add `Column` operators, a `DatabaseValueConvertible` wrapper type, or a custom `Date.databaseValue`. Overriding GRDB's `Date` conformance isn't possible, and a second spelling would split the convention.
- No other app code changes. No repository uses a date filter yet. Phase 2's `DailyReviewBuilder` (ARCHITECTURE §10.2, line ~508: "due non-suspended cards (`dueAt ≤ now`)", plus the `introducedToday` and `lastCompletedAt` cutoffs) will be the first user and must write `Column("dueAt") <= now.databaseUnixSeconds`. ARCHITECTURE already says this; don't edit it.

## Tests (add to `@Suite struct DateStorageTests`)
Add one private helper to the suite. It inserts a document, one highlight and two passive review cards, one due a day before `TestData.referenceDate` and one a day after:
```swift
    private static let pastCardId = "30000000-0000-0000-0000-0000000000c1"
    private static let futureCardId = "30000000-0000-0000-0000-0000000000c2"

    /// Inserts a document, a highlight and two cards due one day before and one day after `TestData.referenceDate`.
    private static func insertPastAndFutureCards(_ db: Database) throws {
        let documentId = "10000000-0000-0000-0000-0000000000c1"
        let highlightId = "20000000-0000-0000-0000-0000000000c1"
        try TestData.document(id: documentId).insert(db)
        try TestData.highlight(documentId: documentId, id: highlightId).insert(db)
        try TestData.reviewCard(highlightId: highlightId, id: pastCardId,
                                dueAt: TestData.referenceDate.addingTimeInterval(-86_400)).insert(db)
        try TestData.reviewCard(highlightId: highlightId, id: futureCardId,
                                dueAt: TestData.referenceDate.addingTimeInterval(86_400)).insert(db)
    }
```
Each test below:
- uses its own `let appDatabase = try AppDatabase.makeInMemory()`;
- does all its work inside one `try await appDatabase.writer.write { db in … }`;
- calls the helper as `try Self.insertPastAndFutureCards(db)` where needed;
- calls `try FTSIntegrity.check(db)` as the last statement in that closure, because the helper inserts into FTS-indexed tables (ARCHITECTURE §15).

1. **`dateQueryArgumentsCompareAsUnixSeconds`** (the bug report's failing test, with the helper):
   - `let now = TestData.referenceDate.databaseUnixSeconds`
   - `try ReviewCard.filter(Column("dueAt") <= now).fetchAll(db).map(\.id)` equals `[Self.pastCardId]`.
   - `try ReviewCard.filter(Column("dueAt") > now).fetchAll(db).map(\.id)` equals `[Self.futureCardId]`.
   - The same `<=` query as raw SQL also returns only the past card: `try String.fetchAll(db, sql: "SELECT id FROM reviewCard WHERE dueAt <= ?", arguments: [now])` equals `[Self.pastCardId]`.
2. **`rawDateArgumentsBindAsText`** (pins the hazard). Put this comment on the test: `// Documents GRDB behaviour that ADR-0012 works around. If this starts failing, GRDB changed how it binds Date: report it, don't delete or "fix" this test.`
   - `try String.fetchOne(db, sql: "SELECT typeof(?)", arguments: [TestData.referenceDate])` equals `"text"`.
   - `try String.fetchOne(db, sql: "SELECT typeof(?)", arguments: [TestData.referenceDate.databaseUnixSeconds])` equals `"real"`.
   - After `insertPastAndFutureCards`, `try ReviewCard.filter(Column("dueAt") <= TestData.referenceDate).fetchCount(db)` equals `2`. This is the wrong result the bug report describes.
   - `try ReviewCard.filter(Column("dueAt") > TestData.referenceDate).fetchCount(db)` equals `0`.
3. **`databaseUnixSecondsMatchesStoredValue`**:
   - Build `let date = Date(timeIntervalSinceReferenceDate: 815_000_000.123).storageRounded`. Insert a document, a highlight and one card with `dueAt: date`. Use new IDs: document `10000000-0000-0000-0000-0000000000c3`, highlight `20000000-0000-0000-0000-0000000000c3`, card `30000000-0000-0000-0000-0000000000c3`. Don't call the helper.
   - `#expect(date.databaseUnixSeconds == date.timeIntervalSince1970)`
   - `try Double.fetchOne(db, sql: "SELECT dueAt FROM reviewCard WHERE id = ?", arguments: [cardId])` equals `date.databaseUnixSeconds` (exact `==`, no tolerance).
   - `try ReviewCard.filter(Column("dueAt") == date.databaseUnixSeconds).fetchCount(db)` equals `1`.
4. **`dateColumnAssignmentsStoreReal`**:
   - Call `insertPastAndFutureCards(db)`. Then `let newDue = Date(timeIntervalSinceReferenceDate: 815_000_000.5).storageRounded`.
   - `_ = try ReviewCard.filter(key: Self.pastCardId).updateAll(db, Column("dueAt").set(to: newDue.databaseUnixSeconds))`
   - `try String.fetchOne(db, sql: "SELECT typeof(dueAt) FROM reviewCard WHERE id = ?", arguments: [Self.pastCardId])` equals `"real"`.
   - `try ReviewCard.fetchOne(db, key: Self.pastCardId)?.dueAt` equals `newDue`.

### Change to an existing test (L7, `DateStorageTests` part only)
In `recordRoundTripIsExact`, add `try FTSIntegrity.check(db)` as the **last statement inside** the existing `try await db.writer.write { db in … }` closure, directly after `try highlight.insert(db)`. Inside that closure `db` is the GRDB `Database` (it shadows the outer `AppDatabase` named `db`), so the call compiles as written. Change nothing else in that test: not its IDs, its sample date, the read, or the `#expect`.

Don't change the other four existing tests (`unroundedDatesCanDrift`, `storageRoundedDatesSurviveUnixSeconds`, `storageRoundedIsOnGridAndClose`, `systemNowIsStorageRounded`) or their sample dates.

If a test fails in a way this spec doesn't predict, report BLOCKED with the exact failure. This applies especially to test 2 returning anything other than `"text"` and `2`. Don't change the helper or the expectations to make it pass.

## Acceptance criteria
1. `Date.databaseUnixSeconds` exists in the existing `extension Date` in `StudyRecord.swift`, matches the "Interfaces to produce" block (a `Double`, no rounding, with the doc comment), and is the only app-code change. → code review of the diff
2. A `dueAt <= now` query built with the helper returns only the past card, and `>` returns only the future card, through both the query interface and raw SQL. → test `DateStorageTests/dateQueryArgumentsCompareAsUnixSeconds`
3. A bare `Date` argument binds as TEXT, and the helper binds REAL. The bare-`Date` filter returns 2 for `<=` and 0 for `>`, which pins the hazard. → test `DateStorageTests/rawDateArgumentsBindAsText`
4. The helper equals the stored value of a record saved with the same date, exactly. → test `DateStorageTests/databaseUnixSecondsMatchesStoredValue`
5. A bulk `updateAll` assignment through the helper stores REAL and decodes back to the same date. → test `DateStorageTests/dateColumnAssignmentsStoreReal`
6. Every new test ends its write closure with `FTSIntegrity.check(db)`. The other four existing `DateStorageTests` are unchanged and pass. → code review of the diff + `./scripts/test.sh StudyReaderTests/DateStorageTests`
7. `recordRoundTripIsExact` ends its write closure with `try FTSIntegrity.check(db)`, its only change in the diff, and still passes. → code review of the diff + test `DateStorageTests/recordRoundTripIsExact`
8. The full suite passes with no new warnings. → test-runner (`./scripts/test.sh`)

## Out of scope
- Any schema change or migration (v1 and v2 are frozen, ADR-0013). The column format stays REAL Unix seconds.
- Changing `StudyRecord`'s encoding or decoding strategies, `storageRounded`, `SystemNow` or `FixedNow`.
- Adding repositories, `DailyReviewBuilder`, or any date-filter query to app code (Phase 1–2).
- Editing ADR-0012 or ARCHITECTURE (already amended for this task).
- The other second-pass low findings. L1 is T27. L2–L6 and the rest of L7 (`UpsertConventionTests`, `ReviewExportRecordTests`, `RecordCodingTests`) are in `docs/bugs/backlog.md`. This task only covers L7's `DateStorageTests` part.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
