# T96: In-memory library cleanup uses the wall clock, not the injected clock

- **Phase:** 2 (preparation; `docs/bugs/backlog.md` L2, "revisit before any test passes a future `FixedNow` to `AppEnvironment.inMemory(now:)`")
- **Agent:** ui-builder
- **Depends on:** none (runs first in Phase 2)
- **ADRs:** ADR-0011 (in-memory environment), ADR-0012 (`SystemNow`)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the unit-test filter in criterion 3.

## Goal
Phase 2 scheduling tests move a `FixedNow` weeks or years ahead. `AppEnvironment.inMemory(now:)` computes its "older than one hour" cleanup cutoff from that injected clock (`now().addingTimeInterval(-3600)`), so a future clock deletes the in-memory folders of every test that is still running in parallel. Compute the cutoff from the real wall clock instead.

## Files to touch
- `StudyReader/App/AppEnvironment.swift` (modify: one line in `inMemory(now:)` and its doc comment)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift` (modify: one test)
- `docs/bugs/backlog.md` is NOT yours: the orchestrator removes L2 there after the commit.

## Interfaces to produce
No signature changes. `inMemory(now:)` keeps `now` for the environment's clock only.

## What to do
1. In `AppEnvironment.inMemory(now:)`, replace `olderThan: now().addingTimeInterval(-3600)` with `olderThan: SystemNow()().addingTimeInterval(-3600)`. `SystemNow` is the only type allowed to read the wall clock (ARCHITECTURE §3), so don't call `Date()` here.
2. Update the doc comment: "Removes in-memory folders older than one hour by the wall clock (`SystemNow`), never by the injected `now`, so a test with a future clock can't delete the folders of tests still running (backlog L2)."
3. Nothing else changes: `removeStaleInMemoryFolders(in:olderThan:)` stays as it is.

## Acceptance criteria
1. `AppEnvironmentTests/inMemoryWithAFutureClockKeepsOtherLibraries` (the failing test from `docs/bugs/phase-0-second-pass.md` L2):
   - `let a = try AppEnvironment.inMemory()`, `defer { TestFileStore.remove(a.fileStore) }`.
   - `_ = try a.fileStore.createDocumentFolder(documentId: UUID().uuidString)`.
   - `let b = try AppEnvironment.inMemory(now: FixedNow(Date(timeIntervalSince1970: 1_900_000_000)))`, `defer { TestFileStore.remove(b.fileStore) }`.
   - `#expect(FileManager.default.fileExists(atPath: a.fileStore.rootURL.path(percentEncoded: false)))`.
   - `#expect(b.now() == Date(timeIntervalSince1970: 1_900_000_000))` (the injected clock is still the environment's clock).
2. The existing `AppEnvironmentTests` (incl. `removeStaleInMemoryFoldersKeepsRecentOnes`) pass unchanged.
3. `./scripts/test.sh StudyReaderTests/AppEnvironmentTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Moving the cleanup into `defaultFactory`.
- Any other `AppEnvironment` change (Phase 2 tasks T99, T105, T115, T120, T122 and T129 change it later).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
