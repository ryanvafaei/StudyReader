# ADR-0013: Frozen migrations, schema goldens, and migration `v2`

- Status: Accepted
- Date: 2026-10-24 (from bug hunt `docs/bugs/phase-0.md` M1, M2, L5; user decision 2026-10-24)

## Context
Migration `v1` is applied on the user's real library (0 documents). GRDB never reruns an applied migration, so editing `SchemaV1` passes every test on fresh databases while the user's database keeps the old schema. The bug hunt found missing FK indexes (M2), a tokenizer that misses ligature and soft-hyphen text from PDFs (M3, ADR-0014; English-only scope), and FTS update triggers that re-index on every `UPDATE` (L5). The user chose a new `v2` migration and keeping `v1` unchanged.

## Decision
- **A migration is frozen as soon as its task is committed** (the user may launch the app at any time after a commit). Corrections always go into a new migration. `SchemaV1` and, once T19 is committed, `SchemaV2` are frozen.
- **Schema goldens.** Each migration `vN` has `StudyReaderTests/Fixtures/schema/vN.sql`: the schema dump (`SchemaSnapshot.dump`) after migrating up to `vN`, checked by `SchemaSnapshotTests/vNIsFrozen`. A golden is copied from the failing test's output, never hand-written, and never regenerated after commit. A failing frozen test means "revert your edit", not "update the golden". If a GRDB update changes generated SQL in an old golden, stop and ask the user.
- **Upgrade tests** start from `V1FixtureDatabase` (a populated v1 database built from frozen raw SQL, in memory and on disk). Each new migration adds a test that upgrades it and checks data and search.
- `AppDatabase.migrator.migrations` only grows by appending (`SchemaSnapshotTests/registeredMigrationsInOrder`).
- **`v2` (`SchemaV2.migrate`)**, one migration, in this order:
  1. FK child indexes: `document_category`, `documentTag_tag`, `reviewLog_card (cardId, reviewedAt)`, `reviewLog_themedReview`.
  2. Drop the 12 GRDB sync triggers (`__<fts>_ai/_ad/_au`) and the four FTS tables.
  3. Recreate the four external-content FTS tables with `tokenize='studyreader'` (ADR-0014).
  4. Hand-written triggers `<fts>_ai`, `<fts>_ad`, `<fts>_au`. The update trigger is `AFTER UPDATE OF <indexed columns>`, so position, progress, color and status saves don't touch the index.
  5. `'rebuild'` each FTS table.
- From `v2` on, FTS tables use hand-written triggers in this pattern. Never use `synchronize(withTable:)` again: its update trigger has no column filter.
- `UPDATE OF` fires when a column appears in the `SET` list, even if its value is unchanged. A full record `update(db)` sets every column, so it still re-indexes. Frequent non-text saves (reading position, progress, `lastOpenedAt`, color, status) must use `update(db, columns: [...])` or `updateChanges(db, from:)` (Phase 1 specs must say so).

## Alternatives considered
- Delete the dev library and keep editing `v1`: rejected by the user.
- `eraseDatabaseOnSchemaChange`: forbidden by ADR-0012, and it would delete user data.
- Keep the GRDB triggers and debounce position writes in Phase 1: every metadata save would still rewrite FTS postings.
- A committed binary `.sqlite` v1 fixture: the sandboxed test host can't write into the repo to produce it, and binary files can't be reviewed. Raw SQL plus the v1 golden pins the same thing.

## Consequences
- Fresh and upgraded databases go through the same migrations. The goldens catch edits to any shipped migration.
- The FTS DDL is now hand-written, so the `v2` golden is its only guard. Reviewers compare it with the SQL in the T19 spec.
- `.claude/agents/data-layer.md` still says FTS uses `synchronize(withTable:)` with `unicode61`. The user has to update that file, because agents can't edit it.
