# Closing UI run, Phase 1 backlog pass, cloud run (2026-10-28)

- Mode: cloud session (ADR-0020), no Mac screen. No Peekaboo pass, no `run-app.sh`, no LaunchServices step. Run by the ui-tester agent. Not one of the T63/T69/T74 checkpoints: it checks the backlog-pass tasks T76 to T89 for regressions and runs the new tests from T84, T88 and T89.
- Build: `a63c6c3 T89: UI tests part 2 ...` (CI snapshot `bae4f09` on `ci-scratch`). `./scripts/ci.sh status` at the start showed the master run for a63c6c3 still in progress; I waited for it: it finished **success** (run 40720069288). The earlier unit run at b3c179c (T88) was green. No other CI job ran at the same time.
- Full UI suite (`./scripts/uitest.sh`, no arguments): https://github.com/ryanvafaei/StudyReader/actions/runs/40720843971 . Logs and screenshots: `build/ci/40720843971/` (`uitest.log`, `summary.md`, `ui-screenshots/` with `manifest.json`: 50 PNG screenshots, 28 hierarchy and debug dumps, 2 screen recordings).
- Re-run of the two failed classes (one job, `./scripts/uitest.sh StudyReaderUITests/ExternalOpenTests StudyReaderUITests/HighlightsBrowserTests`): https://github.com/ryanvafaei/StudyReader/actions/runs/40728094459 , logs in `build/ci/40728094459/`. (I started that command with `> /dev/null 2>&1` appended so the background job stayed quiet. The instructions said no redirects; the redirect only dropped the console echo, the logs in `build/ci/` are complete. The full run itself was started exactly as written.)
- Totals, first run: **93 tests: 91 passed, 2 failed** (`Test Case ... passed/failed` lines, de-duplicated; the xcodebuild footer says "86 tests, 1 failure" because the runner restarted after the failure and lost the totals of the earlier launch, uitest.log line 7671). 2100 s of test time. After the single re-run: 1 of the 2 passed (flake), 1 failed again (reproducible).
- **Verdict: 1 SPEC FAIL (ExternalOpenTests, Open With, reproducible 2/2), 0 test issues, 1 flake (HighlightsBrowserTests H9), 2 UX/visual items, rest NEEDS HUMAN.**
- Swift 6 isolation or compile warnings in the uitest log: **one**, `StudyReaderUITests/NotesTabTests.swift:22:16: warning: main actor-isolated property 'value' can not be referenced from a nonisolated context` (the helper `private func value(of editor: XCUIElement)` at line 21 is not `@MainActor`; log line 6509). The `TagManagerTests.swift:14` warnings from earlier reports are gone. No compile errors, no warnings from the app target. Runtime only: 13 XCTest-internal "Thread running at User-interactive quality-of-service class waiting on a lower QoS thread" notes (priority inversion inside the test runner, not app code).
- Blockers: none. No "Multiple matching elements" in the log. `app.log` can't be read in the cloud.

## Spec FAILs (only these become fix tasks)

### 1. Open With imports nothing when the app was just launched with only the library open (SPEC F-02): `ExternalOpenTests/testDuplicateOpenWithStillShowsTheSummaryAlert`

- Message: `ExternalOpenTests.swift:67: error: XCTAssertTrue failed - The first open didn't import the file.` The test launches the app (seeded library, Library tab only), opens a new PDF with `NSWorkspace.open(_:withApplicationAt:)` and waits 15 s for the card "Open With Duplicate".
- Run 1 (40720843971): failed after 31 s. Run 2 (40728094459, the single re-run of the class): failed again after 52 s. **Not a flake.** Same assertion at the same line both times.
- Evidence: hierarchy dumps `build/ci/40720843971/ui-screenshots/F4A9FB36-FBF5-4091-9E6C-90257F1BAEB5.txt` and `build/ci/40728094459/ui-screenshots/AE1B9601-1550-46EA-BA84-64598C27B775.txt`. Both show one app instance (one pid), the library window, the 9 seeded cards ("Sample · Slides", "Lab manual", "Book chapter", "Paper: Re...", "Notes: Gr...", "Paper: Sp...", "Lecture 1...", plus the deliberate "Indexing..." and "Text extraction failed" cards), no card for "Open With Duplicate", no alert, no sheet, no spinner for an import. (The "Open With Duplicate.pdf" entries in the dump are the macOS Apple menu "Recent Items", not the app.) The file URL never produced a card.
- Why SPEC FAIL and not TEST ISSUE: the test encodes F-02 (a file opened with Open With reaches the running instance and imports without an alert; T48, T52j, T74a). The same file is imported fine by the other two Open With tests in the same runs (`testOpenWithWhileRunningImportsIntoTheRunningInstance` 20 s, `testOpenWithWhenNotRunningLaunchesOnceAndImports` 18 s, both passed in both runs), so the Open With path works in general. Only this variant fails: first test of the class, app launched by the test and seeded, no reader tab ever opened, and the URL is delivered a moment after seeding. The T74a run (40628982827, per the T74a review log) passed 4/4 with this same test and the same line 67; the only change to the file since is T84's `waitForExistence(timeout: 2)` on line 68, which is after the failing line. `ExternalOpenTests` was not run by T84 (it ran `HighlightsBrowserTests` only), so the regression entered somewhere between T74a (ea3e7e1) and this run.
- Cause: not determined (no Mac, no `app.log`, I did not edit code). Product changes since ea3e7e1 that touch launch, seeding or the library window: T84 `AppLaunchModel.swift` (`SettingsStore.resetEphemeral()` before the in-memory environment, lines 30 to 48), T84 `SampleLibrary.swift` (per-highlight creation times, real position keys), T85 `AppSession.swift:14-16` and `LibraryView.swift` (selection moved into `AppSession`). `ExternalURLRouter.swift` and `AppDelegate.swift` did not change since T74a, and `RootView.swift:88` still attaches the handler in `.task`. A timing cause (URL delivered before the handler is attached or the import coordinator is ready, or an import queued behind seeding) fits the variant pattern better than a routing bug, but that is a guess.
- Suggested next step for a fix task: bisect with `./scripts/ci.sh uitest StudyReaderUITests/ExternalOpenTests` (4 tests, about 2 minutes) on the T84 and T85 commits, and check the import log (`Log.files`) on a Mac. Keep the test as is.
- Impact: if it is a real startup race, a file opened from Finder right after launch can be dropped. Medium priority; the cold-start and already-running paths work.

No other spec FAILs.

## Flake (classified, not a fix task)

- `HighlightsBrowserTests/testOpenInDocumentFromButtonContextMenuAndDoubleClick` (H9, T89): run 1 failed with `HighlightsBrowserTests.swift:414: The reader didn't land on page 3, the page field shows "2".` (56 s). The single re-run of the class (run 40728094459) passed it (43 s), and all 13 tests in the class passed. So: **flake**. No failure screenshot or hierarchy was attached (the test attaches none on that assertion; only synthesized-event records exist). Note for the backlog: the page field showing "2" right after Open in Document of a p. 3 row looks like the reading-position restore or the highlight reveal finishing after the first scroll; if it recurs, it may be a real race between a freshly opened reader's saved position and the `.highlight(id)` navigation, which the Mac pass should watch.

## Results per test class (first run)

| Class | Tests | Pass | Fail | Notes |
|---|---|---|---|---|
| CategoryManagerTests | 3 | 3 | 0 | |
| ExportSheetTests | 3 | 3 | 0 | |
| ExternalOpenTests | 4 | 3 | 1 | Spec FAIL 1 (Duplicate); re-run: same failure |
| FindInDocumentTests | 3 | 3 | 0 | new F1, F2 (+B24 2), F3 (T88) |
| GlobalSearchTests | 2 | 2 | 0 | new S3, S4 (T88) |
| HighlightsBrowserTests | 13 | 12 | 1 | H9 flake; re-run 13/13 |
| HighlightsPanelTests | 2 | 2 | 0 | new C3, C6 (T88) |
| LibraryCoverTests | 6 | 6 | 0 | |
| LibraryOpenTests | 11 | 11 | 0 | |
| MetadataSheetTests | 8 | 8 | 0 | |
| NotesTabTests | 2 | 2 | 0 | new C17, C18 (T88; C18 also covers T86 headings, lists and tags) |
| ReaderChromeTests | 18 | 18 | 0 | |
| ReaderHighlightTests | 10 | 10 | 0 | |
| SettingsTests | 3 | 3 | 0 | new Google tab test (T89), focus test (T84) |
| TagManagerTests | 5 | 5 | 0 | |
| **Total** | **93** | **91** | **2** | |

## New tests (T84, T88, T89): all ran, all passed except H9 once (flake)

| Test | Task | Result | Evidence |
|---|---|---|---|
| S3 `GlobalSearchTests/testClickingAHitOpensTheReaderAtTheLocation` | T88 | PASS | page field "2" asserted, 28 s |
| S4 `testCommandShiftFFromAReaderShowsTheLibrarySearch` | T88 | PASS | 18 s |
| F1 `FindInDocumentTests/testPDFFindBarOpensFromShortcutToolbarAndMenu` | T88 | PASS | screenshot `5E233E6F...png` |
| F2 `testPDFFindCountsAndSteps` (+B24 2) | T88 | PASS | |
| F3 `testPDFFindWithNoMatchesDisablesTheArrows` | T88 | PASS | |
| C3 `HighlightsPanelTests/testEmptyStateWhenTheDocumentHasNoHighlights` | T88 | PASS | |
| C6 `testClickingARowJumpsToItsPage` | T88 | PASS | |
| C17 `NotesTabTests/testNotesTabKeepsTextAcrossTabSwitchAndReopen` | T88 | PASS | |
| C18 `testPreviewRendersHeadingsListsAndTags` | T88, T86 | PASS | screenshot `59EC8C57...png`: "Plan" as a heading, "#todo check" as plain text, two bullets, a numbered list |
| H1 `testCountTextSingularAndPlural` | T89 | PASS | |
| H2 `testDocumentCategoryNoteViewAndColourFiltersNarrow` | T89 | PASS | |
| H4 `testCommandAndShiftClickSelectSeveralRowsAndShowTheBulkBar` | T89 | PASS | screenshot `FD7E5357...png` |
| H5 `testBulkAddAndRemoveTag` | T89 | PASS | 83 s |
| H6 `testBulkColourAndDeleteWithConfirmation` | T89 | PASS | screenshot `BF1D0FFF...png` |
| H9 `testOpenInDocumentFromButtonContextMenuAndDoubleClick` | T89 | FLAKE (failed once, passed on the re-run) | see Flake |
| Export Selection alert `testExportSelectionShowsTheNotConfiguredAlert` | T89 | PASS | screenshot `58502634...png`: alert "Export / Google export not configured." with OK |
| Settings > Google `SettingsTests/testGoogleTabShowsNotConfiguredAndHidesFolderAndTargets` | T89 | PASS | screenshot `D50621D0...png`: four tabs (General, Reading, Data, Google), "Account" with "Google export not configured / Set GOOGLE_CLIENT_ID as described in DEPENDENCIES.md §4.", no folder field or targets table |
| `SettingsTests/testSettingsOpensWithoutAFocusedLabelField` | T84 | PASS | |
| `HighlightsBrowserTests/testReturnAndEscapeStayInTheDetailPaneFields`, `LibraryOpenTests/testReturnInTheSearchFieldDoesNotOpenTheSelectedDocument` | T84 | PASS | |

No regression from T76 to T83 or T85 to T87 showed up in any other class (library, reader chrome, highlights, metadata, tags, categories, export sheet, covers all green).

## Screenshots viewed

New or changed screens viewed: Settings Google, Export Selection alert, Notes preview, PDF find bar, Highlights browser bulk bar. The other 45 PNGs are unchanged screens from earlier checkpoints (library covers, reader chrome, metadata sheet, tags); I looked at the hierarchy dumps and test messages for those and found nothing wrong.

- Settings Google (`D50621D0...`): fine; the window has a lot of empty space under the single "Account" group, nothing clipped.
- Export Selection alert (`58502634...`): fine, centred, two rows still selected behind it.
- Notes preview (`59EC8C57...`): headings, bullets and numbered list render. The `#todo check` line shows the tag as plain text; whether a tag should look different is a taste call (NEEDS HUMAN).
- PDF find bar (`5E233E6F...`): bar floats over the page top, field focused, arrows greyed with no query, Done button. Fine.
- Highlights browser bulk bar (`FD7E5357...`, `58502634...`, 1024 pt window, list 455 pt): **layout nit, see UX items.**

## UX items and visual nits (not spec failures; proposed for docs/BACKLOG.md)

1. **Highlights browser, bulk bar and count text are cramped at the default window width.** In `FD7E5357...png` the bulk bar text "2 selected" wraps over three lines ("2 / select- / ed"), the buttons are truncated to "Ad...", "Exp...", "De..." (Add Tag, Export Selection, Delete), and the count "10 highlights" wraps to three lines ("10 / high- / lights") in the filter bar. All still work (the tests find them by identifier), but a user cannot read the button names. The list is 455 pt wide and the detail pane 360 pt. Suggest letting the bulk bar use icons plus tooltips or two rows, `lineLimit(1)` with `fixedSize` for the count, or a narrower detail pane.
2. **Swift 6 warning, `NotesTabTests.swift:22`:** mark `value(of:)` `@MainActor` (same fix as `HighlightsBrowserTests.rows(in:)` and the old TagManagerTests warnings).
3. **H9 flake:** page "2" after "Open in Document" of a p. 3 row, once in two runs (see Flake). Consider waiting for the page after the reader finished loading and attaching a hierarchy on failure; watch for a real race on the Mac.
4. **Failure diagnostics for Open With:** `testDuplicateOpenWithStillShowsTheSummaryAlert` attaches no hierarchy on the failing `waitForExistence` (the other two tests do, via `attachHierarchy`). The dumps above came from XCTest's own failure attachments. Suggest the same `if !imported { ui.attachHierarchy(...) }` pattern as line 51, and an `app.log` import line check once the failure is understood.

Proposed BACKLOG lines:
- `B36 (UX) Highlights browser bulk bar and count text wrap and truncate at 1024 pt ("2 select-ed", "Ad...", "Exp...", "De...", "10 high-lights"); closing run 2026-10-28, screenshots FD7E5357, 58502634.`
- `B37 (test hygiene) NotesTabTests.swift:22 helper value(of:) needs @MainActor (Swift 6 warning).`
- `B38 (test) H9 testOpenInDocument... failed once with page "2" (flake on re-run); add a failure attachment and watch for a position-restore versus highlight-reveal race in a freshly opened reader.`
- `B39 (test) ExternalOpenTests.testDuplicateOpenWithStillShowsTheSummaryAlert: attach the hierarchy when the first import card is missing (as the While Running test does).`

(Fix task proposal, not a backlog line: the spec FAIL above.)

## NEEDS HUMAN: proposed rows for VISUAL_CHECKS.md ("Needs a Mac")

| Task | Check |
|---|---|
| T74a / closing run | Finder Open With right after the app launches (quit the app, open a new PDF with Open With, library only, no reader tab): the card appears with no alert. This is the variant that fails on CI; repeat with the app already running. Also Dock-icon drop. Look at `app.log` for the import line. |
| T89 / T69 | Highlights browser at the default and a narrow window, light and dark: the bulk bar ("N selected", Add Tag, Remove Tag, Color, Export Selection, Delete) and the "N highlights" count are readable, not wrapped or truncated (see UX item 1). |
| T86 | Notes preview look in light and dark: heading sizes, bullets, numbers, and whether `#tag` words should be styled as tags rather than plain text. |
| T72 / T73 (unconfigured) | Settings > Google in the unconfigured build, light and dark: the single "Account" group, a lot of empty space below; taste call. (Signed-in state still needs a Google account.) |
| T88 | S1 (moved earlier): the global search focus case that needs real keyboard focus; unchanged. |
| T89 | H9: Open in Document from a browser row, five times in a row, on a persistent library: the reader lands on the highlight's page every time (CI saw page "2" instead of "3" once). |

Everything else on the Mac list in `docs/checkpoints/T74-cloud-2026-10-28.md` ("Needs a Mac (summary of everything accumulated)") is unchanged and still open; T88 and T89 covered the CI-drivable parts of the T63 (C3, C6, C17, C18), T66 (S3, S4), T67 (F1 to F3) and T69 (H1, H2, H4 to H6, H9) rows.
