# T92a: Exports go into the app's own "StudyReader" Drive folder (service side)

- **Phase:** 1 (bug hunt `docs/bugs/phase-1.md` H2; user decision 2026-10-28; SPEC F-21 AC5, ADR-0018 amendment "app folder", ARCHITECTURE §9.2 "App folder")
- **Agent:** integrations. Escalation (CLAUDE.md): Sonnet agent. 1st rejection → same agent, effort `high`, with the spec and the review report. 2nd rejection → stop and ask the user. Reviews after an escalation run code-reviewer with effort `high`.
- **Depends on:** T91 (order only). T92b (Settings UI) runs right after this task.
- **ADRs:** ADR-0018 (+ amendment 2026-10-28), ADR-0015 (settings), ADR-0007
- **Visual check needed:** yes, Mac only, with a real Google account (rows "T92 (1)" and "T92 (2)" in VISUAL_CHECKS.md "Needs a Mac", already added by the architect)
- **UI tests:** none. Verify with `./scripts/build.sh` and unit-test filters only.

## Goal
Under the `drive.file` scope the app can only put files into folders it created itself, so the pasted folder link (SPEC F-21 before 2026-10-28) makes every create fail. From now on every new Doc (first export, Create New Doc, Export Selection) goes into a folder named `StudyReader` that the app creates in My Drive on the first export, remembers per Google account, and reuses. This task changes the export service only; T92b removes the Settings field.

## Decisions (state them in doc comments; don't re-decide)
- **Lookup before create.** When no folder ID is stored for the account (first export, a new Mac, a reinstall, or the stored folder is gone), the service first lists app-visible folders named `StudyReader` that aren't trashed and takes the oldest; it creates one only when none exists. This keeps one folder per account across Macs and reinstalls. (`drive.file` lists only files the app created or the user picked, so a folder the user made by hand is never found.)
- **Deleted or trashed folder → recreate.** Before every create the stored folder is checked with `files.get`. A 404, `trashed: true` or a non-folder MIME type forgets the stored ID and goes through lookup/create, so the export still succeeds and a new `StudyReader` folder appears in My Drive. No error is shown for this.
- **Moved folder → still works.** Drive IDs survive moves; the stored ID is used wherever the folder is now. The check doesn't look at the folder's location.
- **Concurrent first exports → one folder.** Folder resolution runs behind one actor-wide gate (the existing `acquireGate`/`releaseGate` with the reserved key `"#app-folder"`, which can't collide with target UUIDs). The second export waits, re-reads the stored ID after it gets the gate, and verifies and uses the folder the first one made. Lock order: target gate, then folder gate (Export Selection takes only the folder gate), so no deadlock.
- **Per account.** The ID is stored in `SettingsStore` per account; the key is the SHA-256 hex of the trimmed, lowercased email (`Hashing.sha256Hex(of:)`), never the email itself. Signing in with another account uses that account's entry (or creates its folder); signing back in finds the old one. When `currentEmail()` is nil or empty nothing is stored and every create runs the lookup (which still finds the one folder).
- **Older settings ignored.** `settings.googleExportFolderId` (a pasted ID) and a target's existing `googleFolderId` are never used as a parent. A new target is inserted with `googleFolderId: nil`; on a successful create the folder actually used is recorded (as today via `recordResult(folderId:)`).

## Files to touch
- `StudyReader/Features/Export/GoogleExportService.swift` (modify)
- `StudyReader/Features/Export/DriveUploadRequest.swift` (modify: three folder requests)
- `StudyReader/Core/Support/SettingsStore.swift` (modify: per-account folder ID; leave `googleExportFolderId` as it is, T92b renames it)
- `StudyReaderTests/ExportTests/GoogleExportServiceTests.swift`, `DriveUploadRequestTests.swift`, `ExportSheetModelTests.swift` (modify), `StudyReaderTests/CoreTests/SettingsStoreTests.swift` (modify)
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Interfaces to produce
```swift
extension SettingsStore {
    /// ID of the "StudyReader" folder the app uses in this Google account's Drive (ADR-0018 amendment). Stored in one
    /// dictionary under "settings.googleAppFolderIds", keyed by `Hashing.sha256Hex(of: email.trimmed.lowercased())`.
    /// nil for an empty email.
    func googleAppFolderId(forAccount email: String) -> String?
    /// nil removes the entry. Does nothing for an empty email.
    func setGoogleAppFolderId(_ folderId: String?, forAccount email: String)
}

extension DriveUploadRequest {
    static let folderMimeType = "application/vnd.google-apps.folder"
    static let appFolderName = "StudyReader"
    /// GET https://www.googleapis.com/drive/v3/files/{id}?fields=id,mimeType,trashed  (id percent-encoded as in `make`)
    static func folder(id: String, accessToken: String) throws -> URLRequest
    /// GET https://www.googleapis.com/drive/v3/files with query items (built with URLComponents.queryItems):
    /// q = "name = 'StudyReader' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
    /// spaces = drive, orderBy = createdTime, pageSize = 1, fields = files(id)
    static func findAppFolder(accessToken: String) throws -> URLRequest
    /// POST https://www.googleapis.com/drive/v3/files?fields=id, Content-Type "application/json; charset=UTF-8",
    /// body exactly {"mimeType":"application/vnd.google-apps.folder","name":"StudyReader"} (sorted keys, no parents)
    static func createAppFolder(accessToken: String) throws -> URLRequest
}
```
Inside `GoogleExportService` (private, names are suggestions): `resolveAppFolder(token: inout String, logId: String) async -> Result<String, …>` returning the folder ID or the `ExportOutcome` to fail with. All three requests go through the existing `send(token:logId:build:)` so 401 refresh, 429/5xx backoff, offline and cancellation behave exactly as for uploads, and a refreshed token is reused for the upload.

## What to do
1. **Order of requests for a create** (`googleFileId == nil`, Export Selection): token → `about` (once per account, unchanged) → folder resolution → upload `POST`. Updates (`PATCH`) do no folder work.
2. **Folder resolution** (under the folder gate):
   - Read the stored ID for `currentEmail()`.
   - If there is one: `folder(id:)`. Success with `mimeType == folderMimeType` and `trashed != true` → use it. Success otherwise, or `.denied` (403/404 today; T94 refines 403) → forget the stored ID and continue with the lookup. Any `.failure(outcome)` → return that outcome (queued, signInRequired, cancelled, busy…).
   - Lookup: `findAppFolder`. Success with a first `files[0].id` → store and use it. Success with no files (or no `files` key) → create. `.denied` → fail with `.failed("Couldn't use the StudyReader folder in Google Drive.")`. `.failure(outcome)` → that outcome.
   - Create: `createAppFolder`. Success with an `id` → store and use it. Missing `id` → `.failed("Google Drive returned an unexpected response.")`. `.denied` → `.failed("Couldn't use the StudyReader folder in Google Drive.")`. `.failure(outcome)` → that outcome.
   - Log only "app folder reused/created/recreated" with the log id; never the folder ID together with the email, never the email.
3. **Wire it in:** `upload(...)` gets the folder from resolution when `fileId == nil` and reports the folder it used (add `folderId: String?` to `UploadSuccess`); `performExport` passes that to `finish(... folderId:)`. Remove `settingsFolderId` and every read of `settings.googleExportFolderId`. `exportScope` inserts new targets with `googleFolderId: nil`. `exportSelection` uses the same resolution.
4. **Doc comments:** the type comment and `exportScope`'s comment say Docs go into the app folder (ADR-0018 amendment); remove "folder from settings".
5. **Tests.** In `GoogleExportServiceTests`:
   - `Harness` gets `seedFolder: Bool = true`; when true it calls `settings.setGoogleAppFolderId("APPFOLDER", forAccount: "student@example.com")`. Add `static let folderOK = StubHTTPClient.Reply.response(status: 200, body: #"{"id":"APPFOLDER","mimeType":"application/vnd.google-apps.folder","trashed":false}"#)`.
   - **Existing tests that create a Doc change only by inserting `Self.folderOK` right before each create `POST` reply and shifting the request indexes and method lists accordingly** (one extra `GET` before each create): `createThenUpdate` (methods `["GET","GET","POST"]` then `+ "PATCH"`, create path/body at index 2), `concurrentExportsOfOneTargetRunOneAfterAnother` (`["GET","GET","POST","PATCH"]`), `exportRemembersContentHashUntilAFailure`, `errorsUnauthorizedRefreshesOnce` (replies `[about, folderOK, 401, ok]`, headers `["Bearer token","Bearer token","Bearer token","Bearer token-refreshed"]`; second part `[about, folderOK, 401, 401]`), `errorsDocMissing` (`["GET","GET","POST","PATCH","GET","POST"]`), `errorsForbiddenUpdate`, `errorsCreateRefusedIsFailure`, `errorsRateLimitBackoff` (both harnesses), `cancelledRequestRecordsNothing` and `cancelledBackoffRecordsNothing` (insert `folderOK` so the cancel still hits the upload), `errorsOtherStatusDoesNotLeakBody`, `htmlFallback` (`body(2)`), `selectionCreatesNoTarget` (`["GET","GET","POST"]`, `body(2)`), `aboutIsAskedOncePerAccount` (`["GET","GET","POST","GET","POST"]`). No other expectation in them may change. `errorsOffline`, `errorsSignInRequiredFromAuth`, `errorsNotConfigured`, `updateRefreshesTokenOnce401` stay as they are.
   - Replace `folderFromSettings` with the tests in the acceptance criteria.
   - `ExportSheetModelTests/exportShowsOutcome`: replies become `[about, {"files":[]}, {"id":"APPFOLDER"}, {"id":"FILE1"}]` (no seeded folder; lookup finds none, the folder is created); its expectations don't change.
   - For the concurrency test, add a private routing stub in the test file (an actor `HTTPClient` that answers by method and path instead of a FIFO queue, and counts folder creates), because two concurrent flows make a queue's reply order nondeterministic.

## Acceptance criteria
1. `GoogleExportServiceTests/appFolderCreatedOnFirstExport`: no seeded folder; replies `[about, {"files":[]}, {"id":"APPFOLDER"}, ok FILE1]`; outcome `.exported(fileId: "FILE1")`; request paths in order `/drive/v3/about`, `/drive/v3/files` (GET, `q` query item exactly as in the interface), `/drive/v3/files` (POST, body `{"mimeType":"application/vnd.google-apps.folder","name":"StudyReader"}`), `/upload/drive/v3/files`; the upload body contains `"parents":["APPFOLDER"]`; `settings.googleAppFolderId(forAccount: "student@example.com") == "APPFOLDER"`; the target's `googleFolderId == "APPFOLDER"`.
2. `GoogleExportServiceTests/appFolderReusedFromAnEarlierExport`: no seeded folder; lookup reply `{"files":[{"id":"OLDFOLDER"}]}`; no folder `POST`; parents `["OLDFOLDER"]`; stored ID `OLDFOLDER`.
3. `GoogleExportServiceTests/appFolderStoredIdIsVerifiedAndReused` (seeded): requests `GET about`, `GET /drive/v3/files/APPFOLDER` (query `fields=id,mimeType,trashed`), `POST` upload; no lookup, no folder create.
4. `GoogleExportServiceTests/appFolderRecreatedWhenTrashed`: seeded; folder GET answers `{"id":"APPFOLDER","mimeType":"application/vnd.google-apps.folder","trashed":true}`, lookup `{"files":[]}`, create `{"id":"NEWFOLDER"}`, upload ok → exported, parents `["NEWFOLDER"]`, stored ID `NEWFOLDER`. Same test (second harness): folder GET answers 404 → same result.
5. `GoogleExportServiceTests/appFolderMovedStillWorks`: seeded; the folder GET answers 200 with the folder (as Drive does after a move; no parents are checked) → used without lookup or create. (Documents the decision; the real move is the Mac check.)
6. `GoogleExportServiceTests/appFolderConcurrentFirstExportsCreateOneFolder`: no seeded folder, routing stub (lookup → `{"files":[]}` until a folder was created, then `{"files":[{"id":"APPFOLDER"}]}`; folder GET → folderOK; folder POST → `{"id":"APPFOLDER"}`; upload POST → a new id each); `async let` two `exportScope` calls with different scopes (`.all` and `.document(docId)`); both `.exported`; exactly one folder `POST`; both upload bodies have `"parents":["APPFOLDER"]`.
7. `GoogleExportServiceTests/appFolderIsPerAccount`: two `GoogleExportService` instances over the same repository and the same `SettingsStore`, one with `StubGoogleAuth(email: "a@example.com")`, one with `StubGoogleAuth(email: "b@example.com")` (each with its own `StubHTTPClient`). A's settings entry is seeded with `FOLDER_A`; B's export runs the lookup (`{"files":[]}`) and create (`{"id":"FOLDER_B"}`) and uploads into `FOLDER_B`; afterwards `googleAppFolderId(forAccount: "a@example.com") == "FOLDER_A"` and `…("b@example.com") == "FOLDER_B"`.
8. `GoogleExportServiceTests/appFolderOldSettingsAreIgnored`: the raw key `settings.googleExportFolderId` set to `"PASTED123"` via `h.settings.defaults` and a seeded target with `googleFolderId = "OLDFOLDER"` and no file ID → the create's parents are `["APPFOLDER"]`, never `PASTED123`/`OLDFOLDER`; the target's `googleFolderId` becomes `APPFOLDER`.
9. `GoogleExportServiceTests/appFolderSelectionUsesTheFolder`: `exportSelection` (seeded) sends folder GET then upload with parents `["APPFOLDER"]` and still creates no target.
10. `GoogleExportServiceTests/appFolderLookupRefusedFails`: no seeded folder; lookup answers 403 → outcome `.failed("Couldn't use the StudyReader folder in Google Drive.")`, no upload request, target status `failed`.
11. `DriveUploadRequestTests/folderRequests`: the three builders produce exactly the URLs, methods, headers and body above (compare `q` through `URLComponents(url:resolvingAgainstBaseURL:)?.queryItems`); a folder id with `/` or `?` is percent-encoded.
12. `SettingsStoreTests/googleAppFolderIdPerAccount`: set for `"A@x.com"`, read back for `" a@X.com "`; another email → nil; nil removes; empty email → nil and no write; `defaults.dictionary(forKey: "settings.googleAppFolderIds")` contains no key with `@`.
13. All other `GoogleExportServiceTests`, `ExportSheetModelTests`, `ExportTargetsModelTests`, `HighlightsBrowserModelTests`, `ExportSyncSchedulerTests` pass (with only the reply/index changes listed in "What to do" 5).
14. `./scripts/test.sh StudyReaderTests/GoogleExportServiceTests StudyReaderTests/DriveUploadRequestTests StudyReaderTests/SettingsStoreTests StudyReaderTests/ExportSheetModelTests StudyReaderTests/ExportTargetsModelTests StudyReaderTests/HighlightsBrowserModelTests StudyReaderTests/ExportSyncSchedulerTests` passes; `./scripts/build.sh` succeeds.
15. Reviewer check: no `URLSession.shared`, no `Date()`/`Task.sleep` in logic; the email is never logged or used as a defaults key; folder requests go through `send`; the folder gate is only taken inside a target gate or by Export Selection.

## Out of scope
- Settings UI, `ExportTargetsModel`, `AppSettings`, `DriveFolderLink`, the legacy notice (T92b).
- 403 reason mapping and the trashed-Doc check on update (T94); the Google Picker (BACKLOG B51).
- Moving existing Docs into the new folder.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer integrations Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED, CI green (run 40750045543, 713 tests); no spec deviations; the Settings/AppSettings/ExportTargetsModel reads of googleExportFolderId stay until T92b; HighlightsBrowserModelTests/exportSelectionIgnoresASecondCall now ends failed instead of exported (still asserts what it should); Mac rows T92 (1)(2) in VISUAL_CHECKS
