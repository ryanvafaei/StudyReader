# T94: Drive errors mapped by reason; queued exports are always retried

- **Phase:** 1 (bug hunt `docs/bugs/phase-1.md` M1 and M2; SPEC F-21 "Errors" as amended 2026-10-28; ARCHITECTURE §9.2 "Errors"; ADR-0018 amendment "M1/M2")
- **Agent:** integrations. Escalation (CLAUDE.md): Sonnet agent. 1st rejection → same agent, effort `high`, with the spec and the review report. 2nd rejection → stop and ask the user. Reviews after an escalation run code-reviewer with effort `high`.
- **Depends on:** T92a (folder requests go through `send`), T92b (last edit of `ExportTargetsModel`), T93 (order only)
- **ADRs:** ADR-0018 (+ amendments), ADR-0015 (`Sleeper`), ADR-0007
- **Visual check needed:** no new row (the existing T73 end-to-end row covers offline and Doc missing; the orchestrator adds nothing unless the report asks)
- **UI tests:** none. Verify with `./scripts/build.sh` and unit-test filters only.

## Goal
1. **M1.** `send` maps every 403 and 404 to `.denied`, and an update that is `.denied` becomes "Doc missing". A full Drive, Google's rate limit or daily limit therefore tells the user the Doc is gone, and "Create New Doc" then breaks the Gemini Notebook link. From now on only a 404 or a Doc in the trash is "Doc missing"; every 403 is mapped by Drive's reason, keeps the Doc link, and rate limits are retried with backoff.
2. **M2.** (a) Export Selection saves no target, yet offline it returns `.queued` and the alert promises a later run that never comes. (b) A manual export (Settings Export Now / Create New Doc, the Export sheet) that ends `.queued` while the network path already reports satisfied (DNS failure, captive portal, a dropped connection) waits for the next network change or a relaunch. T80 added the debounced retry only for the scheduler's own exports.

## Drive 403/404 mapping (exact; state it in doc comments)
Reason = the first `error.errors[i].reason` in the JSON body that is in the list below, else the first one present, else none. The body is decoded only for this; never logged or shown. Log the reason name only when it is one of the known values below, else log "other".

| Status / reason | Where | Outcome | Doc link (`googleFileId`) |
|---|---|---|---|
| 429, 5xx (unchanged) | any request | backoff 1/4/16 s via `Sleeper`, then `.failed("Google Drive is busy. Try again later.")` | kept |
| 403 `rateLimitExceeded`, `userRateLimitExceeded` | any request | same as 429 (backoff inside `send`) | kept |
| 403 `dailyLimitExceeded` | any request | `.failed("Google Drive's daily limit for StudyReader is used up. Try again tomorrow.")`, no backoff | kept |
| 403 `storageQuotaExceeded` | any request | `.failed("Your Google Drive storage is full. Free up space, then export again.")` | kept |
| 403 `appNotAuthorizedToFile`, `insufficientFilePermissions` | update | `.failed("StudyReader can no longer write to this Google Doc. Remove the export target and export again to make a new Doc.")` | kept |
| 403 any other reason or no reason | update | `.failed("Google Drive refused the update. Try again later.")` | kept |
| 403 `appNotAuthorizedToFile`, `insufficientFilePermissions`, other, none | create | `.failed("Google Drive refused the upload.")` (unchanged text) | n/a |
| 404 | update | `.docMissing` | kept (Create New Doc clears it, as today) |
| 404 | create | `.failed("Google Drive refused the upload.")` (unchanged) | n/a |
| 200 on update with `"trashed": true` | update | `.docMissing` (the content was written to the trashed Doc; harmless) | kept |
| 403/404 | `about` format check | assume Markdown, cache nothing (unchanged); rate-limit 403 backs off first | n/a |
| 404, or 403 with no/other/permission reason | app-folder `files.get` (T92a) | forget the stored ID, run lookup/create (T92a rule) | n/a |
| 403 storage or daily | app-folder requests | that `.failed` outcome (no lookup/create) | n/a |
| 403 any non-rate reason, 404 | app-folder lookup or create | `.failed("Couldn't use the StudyReader folder in Google Drive.")` unless storage/daily (their text) | n/a |

A failed export is retried by `ExportSyncScheduler` as today (up to 3 times, 60 s apart, for keep-in-sync and queued targets) and by the user's Export Now. No new `ExportStatus` values.

## Queued retries (exact)
- **Export Selection (M2 a):** `exportSelection` maps any `.queued` result to `.failed("Couldn't reach Google Drive. Check your connection and try again.")`. It never returns `.queued`. (`ExportSheetModel.message(for: .queued)` stays as it is; it is still right for saved targets.)
- **Manual exports (M2 b):** new scheduler entry point, called by every manual export of a saved target when it returns:
  ```swift
  extension ExportSyncScheduler {
      /// A manual export of a saved target finished (Settings Export Now / Create New Doc, the Export sheet).
      /// Only `.queued` does something: the target's retry count starts over, and if the network path is satisfied a
      /// retry is scheduled `syncDelay` later (counts toward `maxFailureRetries`, like the scheduler's own queued
      /// results). If the path is unsatisfied, the reconnect retry (`retryQueued`) covers it. Does nothing while the
      /// scheduler isn't running (tests, previews, the in-memory library).
      func manualExportEnded(targetId: String, outcome: ExportOutcome) async
  }
  ```
  Call sites: `ExportTargetsModel.exportNow` and `clearAndExport` (after `export(targetId:)`), `ExportSheetModel.export()` (after `exportScope`, when `targetId` is non-nil). Use `environment.exportSyncScheduler`.
- **At launch:** already covered: `watchNetwork` treats the first satisfied path update as "became satisfied" and runs `retryQueued` (`ExportSyncSchedulerTests/queuedIsRetriedWhenOnlineAtLaunch`). Keep it; add nothing.
- **While the path stays satisfied, a queued target set from outside the scheduler and never reported** (e.g. a crash mid-export) is retried at the next launch; no polling timer is added.

## Files to touch
- `StudyReader/Features/Export/GoogleExportService.swift` (modify: `send`, `upload`, `importsMarkdown`, folder resolution from T92a, `exportSelection`, `ExportOutcome` doc comment)
- `StudyReader/Features/Export/DriveErrorReason.swift` (new)
- `StudyReader/Features/Export/DriveUploadRequest.swift` (modify: update query `fields=id,modifiedTime,trashed`)
- `StudyReader/Features/Export/ExportSyncScheduler.swift` (modify: `manualExportEnded`)
- `StudyReader/Features/Export/ExportTargetsModel.swift`, `StudyReader/Features/Export/ExportSheetModel.swift` (modify: call `manualExportEnded`; nothing else)
- `StudyReaderTests/ExportTests/GoogleExportServiceTests.swift`, `ExportSyncSchedulerTests.swift`, `DriveUploadRequestTests.swift` (modify), `StudyReaderTests/ExportTests/DriveErrorReasonTests.swift` (new)
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Interfaces to produce
```swift
/// Drive's reason for a refused request, from the JSON error body (ARCHITECTURE §9.2). Pure.
enum DriveErrorReason: Equatable, Sendable {
    case rateLimited          // rateLimitExceeded, userRateLimitExceeded
    case dailyLimit           // dailyLimitExceeded
    case storageFull          // storageQuotaExceeded
    case noAccess             // appNotAuthorizedToFile, insufficientFilePermissions
    case other                // any other reason, no reason, or a body that isn't Drive's JSON
    static func parse(_ body: Data) -> DriveErrorReason
    /// The known reason name for logs ("rateLimitExceeded" …), or "other".
    var logName: String { get }
}
```
In `GoogleExportService`, replace `Reply.denied` with `case notFound` (404) and `case forbidden(DriveErrorReason)` (403 that isn't `.rateLimited`; `.rateLimited` takes the 429 backoff branch inside `send`). Each caller maps them per the table.

## Acceptance criteria
1. `DriveErrorReasonTests/parsesReasons`: bodies `{"error":{"errors":[{"domain":"usageLimits","reason":"userRateLimitExceeded"}],"code":403}}` → `.rateLimited`; same with `rateLimitExceeded` → `.rateLimited`; `dailyLimitExceeded` → `.dailyLimit`; `storageQuotaExceeded` → `.storageFull`; `appNotAuthorizedToFile` and `insufficientFilePermissions` → `.noAccess`; `{"error":{"errors":[{"reason":"somethingNew"}]}}`, `{}`, `""`, `"not json"` → `.other`; a body listing `["somethingNew","storageQuotaExceeded"]` → `.storageFull`.
2. `GoogleExportServiceTests/errors403StorageQuotaKeepsTheDocLink`: target with `googleFileId "FILE1"`; PATCH answers 403 `storageQuotaExceeded` → `.failed("Your Google Drive storage is full. Free up space, then export again.")`, target `lastStatus "failed"`, `googleFileId == "FILE1"`, `sleeper.durations` empty.
3. `GoogleExportServiceTests/errors403UserRateLimitBacksOff`: PATCH 403 `userRateLimitExceeded`, then 200 → `.exported(fileId: "FILE1")`, `sleeper.durations == [.seconds(1)]`.
4. `GoogleExportServiceTests/errors403RateLimitBacksOffThenFails`: PATCH 403 `rateLimitExceeded` four times → `.failed("Google Drive is busy. Try again later.")`, durations `[1, 4, 16]` s, `googleFileId` kept, status `failed`.
5. `GoogleExportServiceTests/errors403DailyLimitFailsWithoutBackoff`: → the daily-limit text, no sleeps, link kept.
6. `GoogleExportServiceTests/errors403NoAccessKeepsTheDocLink`: `appNotAuthorizedToFile` and (second harness) `insufficientFilePermissions` → the no-access text, status `failed` (not `docMissing`), link kept.
7. `GoogleExportServiceTests/errors403UnknownReasonFails`: body `""` and body with reason `somethingNew` → `.failed("Google Drive refused the update. Try again later.")`, link kept. The existing `errorsForbiddenUpdate` (403, empty body) is **changed** to expect this outcome instead of `.docMissing`; say so in the report.
8. `GoogleExportServiceTests/errorsTrashedDocIsDocMissing`: PATCH 200 with `{"id":"FILE1","trashed":true}` → `.docMissing`, status `docMissing`, link kept; with `"trashed":false` → `.exported`.
9. `GoogleExportServiceTests/errorsDocMissing` (404 on update) and `exportRemembersContentHashUntilAFailure` (404 → `.docMissing`) pass unchanged; `errorsCreateRefusedIsFailure` passes unchanged.
10. `GoogleExportServiceTests/errors403OnCreateIsRefusedUpload`: create POST 403 `appNotAuthorizedToFile` → `.failed("Google Drive refused the upload.")`; create POST 403 `storageQuotaExceeded` → the storage text.
11. `GoogleExportServiceTests/appFolderRateLimitBacksOff` (T92a folder path): seeded folder; folder GET 403 `userRateLimitExceeded`, then the folder → upload proceeds, one sleep, no lookup request. And folder GET 403 `storageQuotaExceeded` → storage text, no lookup or create request.
12. `GoogleExportServiceTests/selectionOfflineDoesNotPromiseALaterRun`: `exportSelection` with transport `URLError(.notConnectedToInternet)` (on `about`) → `.failed("Couldn't reach Google Drive. Check your connection and try again.")`; `ExportSheetModel.message(for:)` of it doesn't contain "when you're back online".
13. `ExportSyncSchedulerTests/manualQueuedExportRetriesWhileOnline`: scheduler started, path satisfied, a target with `keepInSync` off and status `queued`; `manualExportEnded(targetId:, outcome: .queued)`; advancing the sleeper by `syncDelay` runs exactly one export of that target.
14. `ExportSyncSchedulerTests/manualQueuedExportWaitsForTheNetworkWhenOffline`: path unsatisfied → `manualExportEnded(.queued)` schedules nothing (no export after advancing 60 s); path becomes satisfied → one export (existing reconnect path).
15. `ExportSyncSchedulerTests/manualExportEndedIgnoresOtherOutcomes`: `.exported`, `.failed`, `.docMissing`, `.signInRequired`, `.cancelled`, `.notConfigured` → no export scheduled; and nothing happens before `start()`.
16. `DriveUploadRequestTests`: the two update-URL expectations (lines ~67 and ~106) change to `fields=id,modifiedTime,trashed`; nothing else changes.
17. All other `GoogleExportServiceTests`, `ExportSyncSchedulerTests` (incl. `queuedIsRetriedWhenOnlineAtLaunch`, `queuedWhileOnlineRetriesAfterDelay`, `reconnectRetriesQueued`), `ExportTargetsModelTests`, `ExportSheetModelTests`, `HighlightsBrowserModelTests` pass unchanged.
18. `./scripts/test.sh StudyReaderTests/GoogleExportServiceTests StudyReaderTests/DriveErrorReasonTests StudyReaderTests/DriveUploadRequestTests StudyReaderTests/ExportSyncSchedulerTests StudyReaderTests/ExportTargetsModelTests StudyReaderTests/ExportSheetModelTests StudyReaderTests/HighlightsBrowserModelTests` passes; `./scripts/build.sh` succeeds.
19. Reviewer check: no response body text reaches a log or a `failed` message; `docMissing` comes only from a 404 on update or `trashed: true`; no polling timer; `ExportTargetsModel`/`ExportSheetModel` change only by the `manualExportEnded` calls.

## Out of scope
- M3 (targets of deleted/merged scopes, BACKLOG B40), L9 (colour labels and keep-in-sync, BACKLOG B49).
- Showing "Create New Doc" for permission 403s (the user's rule: only 404 or a trashed Doc is "Doc missing").
- UI text changes beyond what `ExportSheetModel.message(for:)` already shows for `.failed`.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
