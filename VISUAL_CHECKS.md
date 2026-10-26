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
| T52a | Dropping a PDF from Finder onto the List layout imports it: on a row, and on the empty area below the last row; a drop on the grid still imports; no stray button or focus ring in the library window | Debug > Seed Sample Library, switch to List, drag a PDF from Finder onto a row, then onto the empty area below the last row, then switch to Grid and drag another |
| T52b | Tab bar "+" adds no empty tab: open a document so the tab bar shows, click "+" at the right of the tab bar → no "No document" tab, library tab selected, tab count unchanged | Seed Sample Library, open a document, click "+" |
| T52b | Library window keeps its size and position after the last reader tab closes: maximise (Fill), open a document, Cmd+W → no visible jump (watch for a one-frame 10 pt flicker); repeat with two reader tabs, closing one; drag a tab out and back | Seed Sample Library |
| T52b | Resize (drag bottom-right corner) and move the library while a reader tab is open, then close the tab → the new size and position are kept | Seed Sample Library |
| T52b | Known gaps: zoom (green button or titlebar double-click) while a reader tab is open, then close it → zoomed size may be reverted; also try full screen with a reader open, then close it | Seed Sample Library; report what you see |
| T52d | Highlight-colour menu swatches show their colours in light and dark mode (thin outline visible, not harsh); toolbar button shows the current colour; choice kept after reopening | Seed Sample Library, open a document, open the colour menu in both appearances |
| T52e | Landscape cover (Membrane Transport) sits centred and uncropped over a blurred, dimmed copy in the 3:4 frame, same frame as portrait covers, tint looks right in light and dark; Choose Image…/Reset Cover updates the grid card without relaunch, keeping selection and scroll position | Seed Sample Library, edit metadata (⇧⌘M), choose an image, save; compare both appearances |
| T52h | No console warnings: `Picker: the selection "" is invalid`, `-layoutSubtreeIfNeeded on a view which is already being laid out`, `NSHostingView is being laid out reentrantly`. Metadata sheet Category popup appears without a flash of an empty row; two reader tabs join the library window at its size with no flash of a separate window; closing one keeps the library size | `./scripts/run-app.sh`, seed documents, ⇧⌘M then Cancel, open two documents (double-click), close one, `./scripts/run-app.sh stop`, then search `build/app.log` for the three messages; if one remains, note which action triggered it |
