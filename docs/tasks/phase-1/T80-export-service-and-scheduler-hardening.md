# T80: Export service and scheduler hardening: cancelled outcome, queued retry while online, parallel retries, code spans

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B30 (4)(5 test), B31 (3)(4), B34 (1)–(5); SPEC F-21)
- **Agent:** integrations
- **Depends on:** T78 (shares `ExportRepositoryTests.swift`; T79 runs in between)
- **ADRs:** ADR-0007, ADR-0018 (amended 2026-10-28: `cancelled` outcome writes no status)
- **Visual check needed:** no
- **UI tests:** none (unit tests only, stubs)

## Goal
A cancelled upload must not be recorded as a failure, the scheduler must not strand a target in `queued` while the network is up, reset its retry count after a success and retry queued targets in parallel, and the export renderer must not let a multi-line code span start a Markdown block.

## Files to touch
- `StudyReader/Features/Export/GoogleExportService.swift` (modify)
- `StudyReader/Features/Export/ExportSyncScheduler.swift` (modify)
- `StudyReader/Features/Export/ExportRenderer.swift` (modify: `ExportMarkdownSafety` only)
- `StudyReader/Features/Export/ExportSheetModel.swift` (modify: one `case` in `message(for:)` only)
- `StudyReaderTests/ExportTests/GoogleExportServiceTests.swift`, `ExportSyncSchedulerTests.swift`, `ExportRendererTests.swift`, `ExportRepositoryTests.swift` (modify)

## Interfaces to produce
```swift
enum ExportOutcome: Equatable, Sendable {
    // existing cases …
    /// The request or a backoff wait was cancelled. Nothing is written to the target.
    case cancelled
}
```

## What to do
1. **B31 3.** Map `URLError(.cancelled)` and `CancellationError` from `http.send`, and a cancelled backoff sleep (today `.failed("The export was cancelled.")`), to `.cancelled`. `finish(...)` returns `.cancelled` without calling `recordResult` and without touching `exportedHashes` (like `.notConfigured`). `ExportSheetModel.message(for:)`: `.cancelled` → `String(localized: "The export was cancelled.")`. Scheduler `name(of:)`: "cancelled"; no retry for it.
2. **B34 1.** Reset `failureRetries[targetId]` when an export returns `.exported`.
3. **B34 2.** Keep the latest path state in an actor property (`isPathSatisfied`, updated in `watchNetwork`). When an export returns `.queued` while `isPathSatisfied` is true, schedule a debounced retry (`schedule(targetId:)`), counted against `maxFailureRetries` like a failure.
4. **B34 3.** `retryQueued()` runs the queued targets' `syncNow` concurrently (`withTaskGroup`), still checking `isRunning`.
5. **B34 5.** Comment at `acquireGate`: a caller cancelled while waiting for the gate still runs its export when the gate is handed to it.
6. **B30 4.** In `ExportMarkdownSafety.neutralise`, a code span that contains line breaks is copied with each `\n` replaced by a space (CommonMark renders line endings in code spans as spaces, so the rendered text is unchanged, but no line inside it can start a list or heading).

## Acceptance criteria
1. `GoogleExportServiceTests/cancelledRequestRecordsNothing`: the stub HTTP client throws `URLError(.cancelled)` on create → outcome `.cancelled`; the target's `lastStatus`, `lastError`, `googleFileId` are unchanged (`fetchTarget`).
2. `GoogleExportServiceTests/cancelledBackoffRecordsNothing`: 503 then a sleeper that throws `CancellationError` → `.cancelled`, target unchanged.
3. `GoogleExportServiceTests/updateRefreshesTokenOnce401` (B31 4): an existing target with a file ID; PATCH answers 401 then 200 → `.exported(sameFileId)`, `accessToken(forceRefresh: true)` called exactly once.
4. `ExportRepositoryTests/recordResultKeepsFolderWhenNil` (B31 4): a target with `googleFolderId = "F"`; `recordResult(..., folderId: nil, ...)` keeps "F".
5. `ExportRepositoryTests/changeTokenFollowsSameLengthNoteEdit` (B30 5): with `observeChangeToken()` running, `updateNote` "ab" → "ac" emits a new token (bounded wait).
6. `ExportSyncSchedulerTests/successResetsFailureRetries` (B34 1): two failures, then a success, then three more failures → three retries are scheduled after the success (not zero).
7. `ExportSyncSchedulerTests/queuedWhileOnlineRetriesAfterDelay` (B34 2): path satisfied; export returns `.queued` once then `.exported`; advancing the `ManualSleeper` by `syncDelay` runs the second export without any path change.
8. `ExportSyncSchedulerTests/queuedTargetsRetryInParallel` (B34 3, 4): two queued targets and a stub that holds exports until released: after a reconnect both exports are in flight at the same time (count == 2) before release.
9. `ExportSyncSchedulerTests/stopWhileInFlightRunsNothingAfter` (B34 4): stop while a held export runs; release it; no further export starts (follow-up dropped).
10. `ExportRendererTests/multiLineCodeSpanStartsNoBlock` (B30 4): highlight body "`` `a\n- b` ``" renders with no output line starting with `- b` and the code span intact on one line; all export goldens unchanged.
11. Existing `GoogleExportServiceTests`, `ExportSyncSchedulerTests`, `ExportRendererTests`, `ExportRepositoryTests`, `ExportSheetModelTests` pass. `./scripts/build.sh` succeeds.

## Out of scope
Pre-generating Drive file IDs (B31 1, accepted risk), UI in-flight guards (T83), the Google sign-in restore refresh (B32, Mac first), escaping notes/titles in the export (B29, user decision).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
