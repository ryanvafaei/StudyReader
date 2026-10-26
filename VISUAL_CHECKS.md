# Pending visual checks

Phase 1 workflow (user decision 2026-10-25): tasks are committed after tests pass and the code-reviewer approves. Visual checks are batched here and the user checks them at checkpoints: after T52, T63, T69 and T74 (or earlier if a later task builds on a visual decision, or if the main session needs something from the user).

At each checkpoint the main session gives one checklist grouped by screen, with every step numbered and tagged with its task ID, and marks steps that need special data or setup. Before each checkpoint the Debug "Seed Sample Library" is updated so every new feature can be checked without real files.

Since 2026-10-25 (ADR-0019) the checkpoints are run by the **ui-tester** agent: XCUITests (`./scripts/uitest.sh`) plus an exploratory Peekaboo pass on an in-memory build, with a report in `docs/checkpoints/<checkpoint>.md`. The user only answers items marked NEEDS HUMAN.

Anything that fails becomes a small fix task, committed separately.

## Open

| Task | What to check | Needs setup |
|---|---|---|
| T48 | Open With from Finder goes to the running instance (one Dock icon) and imports; also works when the app isn't running (fix in progress) | A PDF in Finder; remove stale app copies first |
| T48 | Landscape (16:9) cover fills a fixed portrait frame, aspect-fit over a neutral/blurred background, sharp at 2x; the light-blue card fill is just the selection state | Debug > Seed Sample Library |
| T48 | Minor: large-file alert with two large files in one batch | Files over 500 MB (optional) |

| T49 | Sidebar > Tags: empty state; list with "N highlights, M documents" counts; Rename… (duplicate name shows inline error), Merge into…, Delete… dialogs; error alert; VoiceOver rows | Debug > Seed Sample Library ("Sample · midterm" / "Sample · mid-term" are the rename and merge candidates) |
| T49 | Tag field (hosted from T50/T62/T69): suggestions, arrow keys reach the field via .onKeyPress (unverified), Return adds, "#Exam" reuses "Exam", chips wrap | Check when a host screen exists |

| T50 | Library: Edit Metadata… from context menu and ⇧⌘M (disabled with no selection); sheet saves title/author/category, Cancel discards them (tags save immediately); empty title shows inline error; Image… / Reset Cover update the card; "Use Current Page" hidden in the library sheet | A PDF, a Markdown file, a PNG/JPG |
| T50 | Sidebar > Categories: built-ins show a lock, no rename/delete; New Category…, Rename…, Delete… (documents move to Other; Settings default resets to "Lecture slides" if it was the deleted one) | none |
| T50 | Tag manager end-to-end with tags added from the sheet (T49 step 16) | none |
| T50 | Light/dark: sheet, cover placeholder, error text | none |

| T52 | Reader opens as a native tab in the library window's tab group; double-click/Return/Open; reopening an open document selects its tab (no duplicate); tab drag-out; toolbar, right inspector, error state, banner, position persisted on close; menu commands (⇧⌘M, ⌘F, zoom, ⌥⌘H, Snapshot) enabled/disabled correctly; "WINDOW TAB FAILURE" console message; restore after quit; Open With and drop with reader tabs open | Debug > Seed Sample Library |

## Passed

- T45 Settings window (user, 2026-10-24)
- T47 Library view (user, 2026-10-25)
- T48 steps 1–4 and 6–12: drop, folder drop, unsupported, duplicate, File > Import, password prompt, Markdown image folder access, toolbar spinner, no onChange warnings, light/dark (user, 2026-10-25)

## Needs a Mac

Checks a cloud session can't run (ADR-0020). The user does them on the Mac, then moves each to Passed or reports it.

| Task | What to check | How |
|---|---|---|
