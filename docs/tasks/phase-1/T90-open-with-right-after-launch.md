# T90: Open With right after launch imports the file (diagnose first, then fix the root cause)

- **Phase:** 1 (closing UI run of the backlog pass, `docs/checkpoints/closing-cloud-2026-10-28.md`, "Spec FAILs" 1; SPEC F-02 import by Open With / double-click / Dock drop)
- **Agent:** ui-builder (app shell). Escalation per CLAUDE.md: 1st rejection → same agent, effort `high`; 2nd rejection → stop and ask the user.
- **Depends on:** T89 (last committed task, `a63c6c3`); context: T74a (`ea3e7e1`, the earlier Open With fix)
- **ADRs:** ADR-0011 (in-memory launch), ADR-0019 (UI tests at checkpoints), ADR-0020 (cloud CI)
- **Visual check needed:** yes (Mac row "T90" in VISUAL_CHECKS.md "Needs a Mac": Finder Open With right after launch)
- **UI tests:** YES, targeted only, **at most 3 runs in total** (see step 1). Never two CI jobs at once.

## Goal
`StudyReaderUITests/ExternalOpenTests/testDuplicateOpenWithStillShowsTheSummaryAlert` fails 2 of 2 at `ExternalOpenTests.swift:67` ("The first open didn't import the file."): the app is launched by the test with a seeded library, only the Library tab is open, a new PDF is opened with `NSWorkspace.open(_:withApplicationAt:)`, and no card "Open With Duplicate" appears within 15 s (no alert, no sheet, no import spinner in the hierarchy dumps). The other two Open With tests (`testOpenWithWhileRunningImportsIntoTheRunningInstance`, `testOpenWithWhenNotRunningLaunchesOnceAndImports`) pass in the same runs. The test passed 4/4 at T74a (run 40628982827), so the regression entered between `ea3e7e1` (T74a) and `a63c6c3` (T89).

Find where the URL is lost, then fix that in product code so a file opened right after launch always imports.

## Evidence and suspects (read before step 1)
- Hierarchy dumps: `build/ci/40720843971/ui-screenshots/F4A9FB36-FBF5-4091-9E6C-90257F1BAEB5.txt` and `build/ci/40728094459/ui-screenshots/AE1B9601-1550-46EA-BA84-64598C27B775.txt` (if `build/ci/` is missing locally, rely on the checkpoint report's summary). The "Open With Duplicate.pdf" entries in the dumps are the Apple menu's Recent Items, not the app.
- Path of a file URL: `AppDelegate.application(_:open:)` → `ExternalURLRouter.split` → `ExternalURLRouter.shared.receive` (buffers until a handler exists) → handler attached in `RootView.swift` `.task` (~line 86-91) → `ImportCoordinator.importURLs` (batches chained on `lastBatch`) → `ImportService.importItems` → document row → `LibraryModel.observe()` → grid card. `ExternalURLRouter.swift`, `AppDelegate.swift` and `RootView.swift:86-91` did not change since T74a.
- Product commits between T74a and T89 (from the git log): T76 search, T77 PDF/rich text, T78 repositories ("private repository writer"), T79 text reader, T80 export scheduler (`startBackgroundWork`), T81 highlight controllers, T82 reader panel, T83 export UI/Settings, **T84 `bfeb9c0`** (`AppLaunchModel.defaultFactory` calls `SettingsStore.resetEphemeral()` before the in-memory environment; `SampleLibrary` per-highlight times and real position keys), **T85 `a1dd097`** (`AppSession.librarySelection`, `LibraryView` selection), T86 (note rules, `TagRepository.addTag(_:toDocuments:)`), T87 export, T88/T89 UI tests only.
- Main suspects: T84 and T85 (launch, seeding, library window). A startup-timing cause (URL delivered before something is ready, or an import queued behind the seed's background work) fits the "only the first-after-launch variant fails" pattern, but **that is a guess**. Rank and rule out at least these with evidence:
  - H1 delivery: `application(_:open:)` is not called at all for this event.
  - H2 consumer: the router buffered the URL and no handler took it (handler not attached, or replaced/reset).
  - H3 queue: `importURLs` ran but the batch is stuck (behind an earlier batch, the import service, the database writer or the seed's background work).
  - H4 display: the document was imported but the card isn't shown (observation stopped, lazy grid not realising the card, label mismatch).
  - H5 result: the import finished quietly without a document (skipped or treated as a duplicate with no alert).

## Step 1: diagnose (bounded)
**No commit bisect.** `scripts/ci.sh` always snapshots the current `HEAD` plus the working tree (`git add -A` on a temporary index) and has no way to run an older commit such as `bfeb9c0` or `a1dd097`; checking those out would move `HEAD`/worktrees and break the "scripts exactly as written" and "never touch history" rules. So reason from the code and use diagnostic UI runs instead. Because `ci.sh` includes uncommitted changes, temporary diagnostic code and a temporary working-tree revert of one suspect hunk ARE allowed in a run, as long as they are removed before the final diff.

UI runs (all via `./scripts/uitest.sh <filters>`, which forwards to CI on Linux; max 3, one at a time, wait for each):
1. **Run 1, diagnostic** (`./scripts/uitest.sh StudyReaderUITests/ExternalOpenTests`). Before it, add only temporary, uncommitted code:
   - A DEBUG-only probe in the app that a UI test can read (for example an `@Observable` counter object shown in the main window's `navigationSubtitle`, or an accessibility element with identifier `diag-open-with`). It shows: file URLs seen by `AppDelegate`, URLs buffered vs delivered by `ExternalURLRouter`, number of `attach` calls, `ImportCoordinator.importURLs` calls, finished batches and the last summary text.
   - In `testDuplicateOpenWithStillShowsTheSummaryAlert`, when the card is missing: attach the hierarchy (`ui.attachHierarchy`, as line 51 does), record the probe text and whether the toolbar "Importing" spinner exists, then click the sidebar "Tags" and back to "Library" and check the card again, then switch the layout to List and check `ui.row("Open With Duplicate")`. These checks only add information; the assertion at line 67 stays as it is.
   - Two temporary variant tests in the same class: `testDiagOpenWithWithoutSeed` (`launch(seed: false)`, then the same open; does the card appear?) and `testDiagOpenWithAfterTheSeedSettles` (`launch()`, wait until all seeded cards exist, then the same open). Each attaches the probe text.
2. **Run 2, confirm the cause.** Either run the fix, or (if run 1 points at one change but doesn't prove it) temporarily revert just that hunk in the working tree and run the same class. Say which in the report.
3. **Run 3, final verification** of the committed diff (no probe, no variant tests, no reverts): `./scripts/uitest.sh StudyReaderUITests/ExternalOpenTests StudyReaderUITests/LibraryOpenTests`.

If run 2 has not confirmed a cause, **stop and report BLOCKED** with the probe values, hierarchy paths and your ranking of H1-H5. Don't spend run 3 on a guess.

## Step 2: fix the root cause
- Fix it in product code, at the stage step 1 identified. A URL that reaches `AppDelegate` must reach `ImportCoordinator.importURLs` exactly once, whatever the launch stage, window or seeding state. `AppDelegate` and `ExternalURLRouter` already buffer URLs until `attach`; check what that does NOT cover. Examples, not prescriptions: the handler is tied to `RootView`'s `.task` and so to a view's lifetime (attaching once where `AppSession` is created, in `AppLaunchModel.start()`, would remove that dependency); something in the in-memory launch path or the seeding step replaces, resets or blocks a stage; the coordinator's batch chain waits on work it shouldn't.
- No `Task.sleep`, delays, retries on a timer or polling in product code. No sleeps or settles added before the open in the committed `ExternalOpenTests`.
- Never weaken or delete `ExternalOpenTests` assertions, add `XCTSkip`, or change the 15 s timeout. Keep the T74a split (`ExternalURLRouter.split`: files → router, other URLs → `GoogleSignInAuth.handle`, each once).
- Keep from the diagnostics only: the hierarchy attachment when the first card is missing in `testDuplicateOpenWithStillShowsTheSummaryAlert` (`if !imported { ui.attachHierarchy("Open With duplicate: no card", to: self) }`, same pattern as line 51; BACKLOG B39). Remove the probe and the variant tests.
- If the cause can be tested without UI (router, launch model, coordinator), add a Swift Testing unit test for it in the matching suite (`StudyReaderTests/AppTests/ExternalURLRouterTests.swift`, `AppLaunchModelTests.swift`, or the import coordinator's suite), named after the behaviour, e.g. `urlsReceivedBeforeTheSessionExistsReachTheCoordinatorOnce`. If it isn't unit-testable, say why in the report.
- One-line fold-in (closing-run warning, BACKLOG B37): in `StudyReaderUITests/NotesTabTests.swift` line 21, mark the helper `private func value(of editor: XCUIElement) -> String` `@MainActor` (same fix as `HighlightsBrowserTests.rows(in:)`).

## Files to touch
- Product: decided by the diagnosis; expected among `StudyReader/App/AppDelegate.swift`, `StudyReader/App/ExternalURLRouter.swift`, `StudyReader/App/AppLaunchModel.swift`, `StudyReader/App/RootView.swift`, `StudyReader/Features/Library/Import/ImportCoordinator.swift`, `StudyReader/Features/Library/LibraryView.swift` (modify).
- Tests: `StudyReaderUITests/ExternalOpenTests.swift` (modify: failure attachment only), `StudyReaderUITests/NotesTabTests.swift` (modify: one `@MainActor`), one unit-test file under `StudyReaderTests/AppTests/` or the import tests (modify).
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Acceptance criteria
1. The report names the root cause with evidence from the probe and the run(s), the run URLs, what each run was for, and the number of UI runs used (≤ 3).
2. `ExternalOpenTests/testDuplicateOpenWithStillShowsTheSummaryAlert`, `testOpenWithWhileRunningImportsIntoTheRunningInstance`, `testOpenWithWhenNotRunningLaunchesOnceAndImports` and `testNoStaleCopyIsRegisteredWithLaunchServices` pass in the final run 3 (`./scripts/uitest.sh StudyReaderUITests/ExternalOpenTests StudyReaderUITests/LibraryOpenTests`); all `LibraryOpenTests` pass in the same run.
3. Reviewer check on the diff: no assertion, timeout or test removed or weakened in `ExternalOpenTests`; no sleep, delay, timer retry or polling added to product code or before the open in the test; no DEBUG probe or `testDiag…` test left; `ExternalURLRouter.split` behaviour unchanged.
4. The fixed logic has a unit test (name given in the report) that fails without the fix → `./scripts/test.sh StudyReaderTests/<Suite>` green; existing `StudyReaderTests/ExternalURLRouterTests` and `StudyReaderTests/AppLaunchModelTests` still pass. If not unit-testable, the report says why and the reviewer agrees.
5. `NotesTabTests.swift`'s `value(of:)` is `@MainActor`; the run-3 `uitest.log` has no Swift 6 isolation warning from `ExternalOpenTests.swift` or `NotesTabTests.swift` (quote it or write "none").
6. `./scripts/build.sh` succeeds.
7. Visual check (Mac, VISUAL_CHECKS.md row "T90"): quit StudyReader, launch it, and with only the library open use Finder Open With on a new PDF right away → the card appears, no alert; repeat with the app idle for a minute, and with a Dock-icon drop.

## Out of scope
- The H9 flake (`HighlightsBrowserTests/testOpenInDocumentFromButtonContextMenuAndDoubleClick`, BACKLOG B38) and the browser bulk-bar layout (B36).
- Any change to Google sign-in beyond keeping its redirect routed as T74a left it; any new import feature or UI; Finder/LaunchServices registration (`lsregister-clean.sh` is Mac-only).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
