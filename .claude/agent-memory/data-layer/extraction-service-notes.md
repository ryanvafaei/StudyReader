---
name: Extraction service and library maintenance notes
description: T44 ExtractionService actor, DocumentTextRepository, LibraryMaintenance, launch sweep; test patterns and pitfalls
metadata:
  type: project
---

T44 added `DocumentTextRepository` (Core/Repositories), `ExtractionService` (actor, Features/Extraction) and `LibraryMaintenance` (struct, Features/Extraction). Wired in `AppEnvironment`: `startBackgroundWork()` re-queues pending/outdated ids; `make` (not `inMemory`) removes orphan document folders. `AppLaunchModel.start()` calls `startBackgroundWork` after `.ready`.

**Why:** startup must finish extraction left over from a crash and remove folders from interrupted imports (ADR-0016).

**How to apply:**
- `ExtractionService.extract` throws `.missingFile` after marking the row failed; a missing document row is skipped silently (returns). Tests for the skip path should delete the row before calling `extract`, not race the worker.
- `#expect(throws:)` with an async closure needs `await #expect(throws:)`. Build error otherwise.
- `LibraryMaintenance.documentIdsNeedingExtraction` excludes `.failed` rows on purpose (no auto-retry).
- Tests live in `StudyReaderTests/ExtractionTests/` (ExtractionServiceTests: 6 tests, LibraryMaintenanceTests: 3 tests). Both suites pass (9/9).
- Not committed: the implementer leaves commits to the orchestrator.
