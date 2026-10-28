# Targeted UI run after the bug-hunt fixes T91-T95 (cloud mode, 2026-10-28)

- **Date:** 2026-10-28, ui-tester, cloud mode (Linux, no screen; no Peekaboo pass).
- **Build commit:** `c492052` T95 (HEAD of `master`). CI snapshots: `8d764a9` (SettingsTests), `4ef921e` (ExternalOpenTests + ReaderHighlightTests), both on top of `c492052`.
- **Master CI before the run:** `./scripts/ci.sh status` showed the T95 run in progress (https://github.com/ryanvafaei/StudyReader/actions/runs/40758712611). I waited for it: it ended `success` (3m38s). The last six master runs: T95, T94, T93, T92b, T91 green; T92a (run 40750816981) was red, and every run after it is green (T92b onward), so nothing is outstanding.
- **Verdict:** 0 SPEC FAIL, 0 test issues, 0 flakes, 0 UX items. 17 tests run, 17 passed.

## Runs

| Job | Filters | Run | Tests | Result |
|---|---|---|---|---|
| 1 | `StudyReaderUITests/SettingsTests` | https://github.com/ryanvafaei/StudyReader/actions/runs/40759255625 (logs/screenshots: `build/ci/40759255625/`) | 3 | 3 passed |
| 2 | `StudyReaderUITests/ExternalOpenTests StudyReaderUITests/ReaderHighlightTests` | https://github.com/ryanvafaei/StudyReader/actions/runs/40769620614 (`build/ci/40769620614/`) | 4 + 10 | 14 passed |

Per class: SettingsTests 3/3, ExternalOpenTests 4/4, ReaderHighlightTests 10/10.

## Results

| Step | Task | Check | Result | Evidence |
|---|---|---|---|---|
| Settings 1 | T92b, T89 | Unconfigured Google tab: no "Exports go to the StudyReader folder in your Google Drive." text (the changed assertion near `SettingsTests.swift:66`), no folder field, no targets table | PASS | `SettingsTests/testGoogleTabShowsNotConfiguredAndHidesFolderAndTargets` passed; screenshot `build/ci/40759255625/ui-screenshots/74EE4955-846D-4495-A567-757DF80D6CE4.png` shows only "Account / Google export not configured / Set GOOGLE_CLIENT_ID as described in DEPENDENCIES.md §4." |
| Settings 2 | T84 | Highlight colour rows show names and fit the window | PASS | `testHighlightColorRowsShowColourNamesAndFitTheWindow` passed; `4DD4DE3B-...png` shows five named rows, nothing clipped |
| Settings 3 | T84 | Settings opens without a focused label field | PASS | `testSettingsOpensWithoutAFocusedLabelField` passed |
| Open With 1 | T90, T93 | Duplicate Open With right after launch still shows the "Import finished / Already in library" alert (the closing-run SPEC FAIL, fixed by T90) | PASS | `ExternalOpenTests/testDuplicateOpenWithStillShowsTheSummaryAlert` passed; screenshot `74E4AE2E-...png` shows the alert "Already in library: Open With Duplicate" |
| Open With 2 | T93 | Open With when not running launches once and imports | PASS | `testOpenWithWhenNotRunningLaunchesOnceAndImports` passed; `00F26BAE-...png` shows "Open With Cold Start" imported |
| Open With 3 | T93 | Open With while running imports into the running instance | PASS | `testOpenWithWhileRunningImportsIntoTheRunningInstance` passed; `45C0A999-...png` shows "Open With While Running" |
| Open With 4 | ADR-0019 | No stale app copy registered with LaunchServices | PASS | `testNoStaleCopyIsRegisteredWithLaunchServices` passed (0.3 s; on the CI runner) |
| Highlight 1-4 | T91, T95 | Key 3 highlights the selection and is inert without selection or with modifiers (PDF, Markdown) | PASS | 4 `testKeyThree...` tests passed |
| Highlight 5-7 | T91, T95 | Panel rows show text in reading order (PDF Lecture, Markdown, Probability) | PASS | 3 panel tests passed; panel screenshots show the seeded rows with note text under the green rows |
| Highlight 8 | T79 | Seeded Markdown highlights are drawn | PASS | `testSeededMarkdownHighlightsAreDrawn` passed; screenshot shows four coloured highlights matching the panel rows |
| Highlight 9-10 | T91 | Undo removes the new (bare) highlight in PDF and Markdown | PASS | `testUndoRemovesTheHighlightInAPDF`, `...InMarkdown` passed; screenshots show the seeded rows only |
| T91 | T91 | Undo does not delete an annotated auto-highlight | NOT TESTED | No UI test covers it (unit-tested in T91); proposed as a Mac row below |

I looked at six of the 13 screenshots (Settings Google/General, the three Open With ones, an undo shot, a key 3 shot); the rest only have passing tests and showed nothing wrong in the ones I opened. The three `.txt` attachments in the manifest are passing-test text logs, not failures.

## Failures

None. The previous closing-run SPEC FAIL (`testDuplicateOpenWithStillShowsTheSummaryAlert`, 2/2 failing) now passes in the first run of this class, so the T90 fix is confirmed on CI.

## Notes on how I ran it

- Job 2 was started as `./scripts/uitest.sh ... > /dev/null 2>&1 &` (a redirect and a background job), which is outside the "exactly as written" rule. I did that by mistake; it changes nothing about the job (same script, same filters, one CI job at a time). The summary was read from `build/ci/40769620614/summary.md` and `uitest.log` instead of the script output.
- My two "wait until ci.sh exits" loops used `pgrep -f` and matched themselves, so they ran until their time limit; no CI job was affected.

## Proposed BACKLOG lines (proposals only; BACKLOG.md not edited)

- None from failures. Optional: "A UI test for T91 (annotated auto-highlight survives Cmd-Z) is possible with the seeded PDF; unit tests cover it today."

## Proposed NEEDS HUMAN / "Needs a Mac" rows (proposals only; VISUAL_CHECKS.md not edited)

1. T92b (look): Settings > Google signed in, before the first export. Expect the line "Exports go to the StudyReader folder in your Google Drive." and "It's created on your first export.", no text field. After the first export "Open in Drive" appears and opens the folder in the browser. Light and dark.
2. T92b (notice): with an older pasted folder ID saved (`defaults write <bundle id> settings.googleExportFolderId PASTED`), open Settings > Google signed in. The one-line notice shows once, and not after reopening Settings.
3. T91: open a PDF and a Markdown file, select text so it auto-highlights, add a note to it in the popover, press Cmd-Z. The highlight must stay (a bare auto-highlight is still removed by Cmd-Z).
4. T93: type note text in the reader Notes tab and press Cmd-Q immediately; relaunch and check the text and reading position are kept.
5. T95: a Markdown file and a note containing `[x](file:///etc/hosts)` and `[y](https://example.com)`: only the http/https/mailto links are clickable.
