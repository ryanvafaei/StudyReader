# T99: ReviewCardRepository and ReviewSuspension

- **Phase:** 2 (E2.1 Scheduler; SPEC F-15, F-17, F-19)
- **Agent:** data-layer
- **Depends on:** T97 (`ReviewCardFactory` for tests), T98 (`FrequencyPolicy`)
- **ADRs:** ADR-0012 (writes, dates), ADR-0013 (column-limited updates), **ADR-0021** (suspension rule)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 8.

## Goal
The repository for `reviewCard` rows (reads, bulk passive-card creation, the insert hook later used when a highlight is created) and `ReviewSuspension`, the only code that writes `suspended`/`suspendedReason`. No schema change (ADR-0021).

## Files to touch
- `StudyReader/Core/Repositories/ReviewCardRepository.swift` (new)
- `StudyReader/Core/Repositories/ReviewSuspension.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `let reviewCardRepository: ReviewCardRepository`, built from `database` like the others)
- `StudyReaderTests/CoreTests/ReviewCardRepositoryTests.swift` (new)

## Interfaces to produce
```swift
enum ReviewCardError: Error, Equatable, LocalizedError {
    case notPassive                    // "Only passive cards can be created here."
    // T114 adds: notMasteryCard, highlightMismatch
}

struct ReviewCardRepository: Sendable {
    init(database: AppDatabase)

    func fetch(id: String) async throws -> ReviewCard?
    /// The highlight's cards: passive first, then createdAt ASC, then id ASC.
    func cards(forHighlight highlightId: String) async throws -> [ReviewCard]
    /// Live version of `cards(forHighlight:)`. The first element is the current value.
    func observeCards(forHighlight highlightId: String) -> AsyncValueObservation<[ReviewCard]>

    /// SPEC F-17 bulk "Create review cards". One transaction. For each card (in order): skip it when its highlight
    /// doesn't exist or already has ANY review card (any type), else insert it. Then
    /// `ReviewSuspension.recompute(highlightIds:)` over the inserted highlights. Ignores the category's
    /// `autoCreateCards` (an explicit user action); an Off category makes the new card suspended (.frequencyOff).
    /// Every card must be passive, else `ReviewCardError.notPassive` (nothing written). Returns the number inserted.
    @discardableResult
    func insertPassiveCards(_ cards: [ReviewCard]) async throws -> Int

    /// For use INSIDE another repository's write (HighlightRepository.insert, T100). Inserts `card` only when
    /// `FrequencyPolicy.createsCardAutomatically(frequency:autoCreateCards:)` is true for the category of the card's
    /// highlight (highlight → document → category) and the highlight has no review card yet; then recomputes that
    /// highlight's suspension. Returns true when inserted. Not passive → `.notPassive`. Missing highlight → false.
    static func insertAutomaticPassiveCard(_ card: ReviewCard, _ db: Database) throws -> Bool
}

/// The only writer of reviewCard.suspended / suspendedReason (ADR-0021).
enum ReviewSuspension {
    /// For every card in scope, computes FrequencyPolicy.suspendedReason(cardType:highlightHasMasteryCards:override:category:)
    /// with the category of the card's document and whether the card's highlight has any cloze/qa card, then writes
    /// `suspended = (reason != nil)` and `suspendedReason = reason` with `update(db, columns: ["suspended", "suspendedReason"])`
    /// for rows whose values differ. Returns the number of rows changed. Empty id lists change nothing.
    @discardableResult static func recompute(highlightIds: [String], _ db: Database) throws -> Int
    @discardableResult static func recompute(documentIds: [String], _ db: Database) throws -> Int
    @discardableResult static func recompute(categoryId: String, _ db: Database) throws -> Int
}
```
- One SQL shape for the three scopes, with the scope as a bound-argument condition (`r.highlightId IN (…)`, `h.documentId IN (…)`, `d.categoryId = ?`), for example:
  ```sql
  SELECT r.*, c.frequency AS categoryFrequency,
         EXISTS (SELECT 1 FROM reviewCard m WHERE m.highlightId = r.highlightId AND m.cardType IN ('cloze','qa')) AS hasMastery
  FROM reviewCard r
  JOIN highlight h ON h.id = r.highlightId
  JOIN document d ON d.id = h.documentId
  JOIN category c ON c.id = d.categoryId
  WHERE <scope>
  ```
- Inserts use `insert(db)` (ADR-0012), never upsert or REPLACE.
- `AppEnvironment`: add the property after `highlightRepository`, initialise it in `init` with `ReviewCardRepository(database: database)`. No other change there.

## Acceptance criteria
All tests use `AppDatabase.makeInMemory()` (or an in-memory `AppEnvironment` with `defer { TestFileStore.remove(…) }`), `TestData.document`/`TestData.highlight`, cards from `ReviewCardFactory.passive(highlightId:now:)` and `ReviewCardFactory.mastery(…)`, and end with `try await db.writer.write { try FTSIntegrity.check($0) }` (they write highlights). Set a category's frequency or `autoCreateCards` in tests with a fetched `DocumentCategory` and `update(db, columns:)` inside `writer.write` (T101 adds the repository methods).
1. `ReviewCardRepositoryTests/fetchAndOrder`: a highlight with a qa card created at t+1, a passive card at t+2 and a cloze card at t: `cards(forHighlight:)` returns passive, cloze, qa; `fetch(id:)` finds each; an unknown id is nil.
2. `ReviewCardRepositoryTests/observeCardsEmitsOnInsert`: `observeCards(forHighlight:)` first emits `[]`, then one card after `insertPassiveCards` (bounded wait with `TestWait.until`, `#expect` on its result).
3. `ReviewCardRepositoryTests/bulkInsertSkipsHighlightsWithCards`: three highlights, one already has a qa card, one id is unknown: `insertPassiveCards` of four cards (incl. one for the unknown highlight) returns 2; the qa highlight still has only its qa card; a non-passive card in the list throws `.notPassive` and writes nothing.
4. `ReviewCardRepositoryTests/bulkInsertInOffCategoryIsSuspended`: document in Notes, Notes frequency set to off: the inserted card has `suspended == true`, `suspendedReason == .frequencyOff`.
5. `ReviewCardRepositoryTests/automaticInsertRespectsCategory` (inside `writer.write`): Lecture slides (high, auto on) → true and stored; `autoCreateCards = false` → false; frequency off → false; a second call for the same highlight → false; a cloze card → throws `.notPassive`.
6. `ReviewCardRepositoryTests/recomputeAppliesTheRule`: one highlight with a passive and a cloze card (inserted directly with `insert(db)`, both `suspended = false`): `recompute(highlightIds:)` makes the passive card `.mastery` and leaves the cloze card active (returns 1); setting the cloze card's `frequencyOverride = .off` then `recompute(documentIds:)` → cloze `.user`; category off then `recompute(categoryId:)` → cloze stays `.user`, passive stays `.mastery`; a second document's cards in another category are untouched; a recompute with no changes returns 0.
7. Existing suites that build an `AppEnvironment` still compile and pass (`AppEnvironmentTests`, `AppSessionTests`).
8. `./scripts/test.sh StudyReaderTests/ReviewCardRepositoryTests StudyReaderTests/AppEnvironmentTests StudyReaderTests/AppSessionTests` passes; `./scripts/build.sh` succeeds.
9. Reviewer Grep: no update of `suspended`/`suspendedReason` outside `ReviewSuspension.swift` (inserts write the record's values, then recompute); no `upsert(`; dates bound with `.databaseUnixSeconds` if any appear in SQL.

## Out of scope
- Creating cards when a highlight is created (T100), category writes (T101), ratings and queue queries (T102).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
