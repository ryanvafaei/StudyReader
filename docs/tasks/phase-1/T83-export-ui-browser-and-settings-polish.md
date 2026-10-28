# T83: Export UI guards, browser and Settings polish: no double exports, scope options reset, stable filter bar, no initial label focus

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B26 (2), B27 (2), B33 (1)(2)(3)(4), B35 (2); SPEC F-13, F-21, Settings)
- **Agent:** ui-builder
- **Depends on:** T80 (`ExportOutcome.cancelled`, shares `ExportSheetModel.swift`; T81 and T82 run in between)
- **ADRs:** ADR-0018
- **Visual check needed:** yes, Mac only (filter bar at several widths, Settings first frame, Google tab loading state in a configured build): add one row to VISUAL_CHECKS.md "Needs a Mac"
- **UI tests:** none here (unit tests only). T84 adds the Settings focus UI test and runs the affected UI classes.

## Goal
A double click must not start two exports, the export sheet must not carry one scope's options into another, the Google tab must not flash "not configured" in a configured build, the browser must not keep thumbnails for rows that are gone, its filter bar must not truncate or jump when a filter turns on, and opening Settings must not put the cursor in a colour label with its text selected.

## Files to touch
- `StudyReader/Features/HighlightsBrowser/HighlightsBrowserModel.swift`, `HighlightsBrowserView.swift` (modify)
- `StudyReader/Features/Export/ExportTargetsModel.swift`, `ExportSheetModel.swift` (modify)
- `StudyReader/Features/Settings/GoogleSettingsView.swift`, `SettingsView.swift` (modify)
- `StudyReaderTests/HighlightsBrowserTests/HighlightsBrowserModelTests.swift`, `StudyReaderTests/ExportTests/ExportSheetModelTests.swift`, `ExportTargetsModelTests.swift`, `GoogleSignInAuthTests.swift` (modify; the `GoogleAccountModel` tests live there)

## Interfaces to produce
```swift
// HighlightsBrowserModel
private(set) var isExporting: Bool          // true while exportSelection() runs
// ExportTargetsModel
private(set) var exportingIds: Set<String>  // targets with an Export Now / Create New Doc in flight
// GoogleAccountModel
private(set) var hasLoaded: Bool            // true after the first refresh() finished
```

## What to do
1. **B33 1.** `exportSelection()` returns at once while `isExporting`; sets it around the call. The bulk bar's "Export Selection…" button is disabled while `isExporting`. `exportNow(_:)` and `createNewDoc(_:)` return at once when the id is in `exportingIds`, insert/remove it around the call; the target's "Export Now" and "Create New Doc" menu items are disabled while it is in flight.
2. **B33 3.** `ExportSheetModel.prefillOptions()`: when the current scope has no saved target, set `options = ExportOptions()` (still guarded by `scope == self.scope` after the await).
3. **B33 4.** `GoogleAccountModel.hasLoaded`: set true at the end of `refresh()`. `GoogleSettingsView` shows a small `ProgressView` in the Account section and hides the folder and targets sections until `hasLoaded`.
4. **B26 2.** `HighlightsBrowserModel.loadThumbnails`: after the cancellation check, replace the dictionary with the loaded one (`thumbnails = loaded`), so images of rows no longer listed are dropped.
5. **B27 2.** Filter bar: the date button always shows "Date range" and switches its icon to `calendar.badge.checkmark` when a date filter is on (accessibility value "On"/"Off"); give the date button and the Clear button `.fixedSize()` so nothing truncates or moves when a filter turns on.
6. **B35 2.** Settings opens with no text field focused: no colour-label field becomes first responder on open (e.g. a `@FocusState` that is cleared on appear, or the window's initial first responder set to nil through the existing `WindowAccessor`). A click in a label field still edits it, and commit on focus loss still works.
7. **B33 2.** Tighten `ExportSheetModelTests`: `scopeRequiresId` asserts `scope == nil` for document/tag/category kinds without an id, non-nil `.tag(id)` once an id is set (currently the tag case is missing and one assertion is vacuous); `notConfiguredMakesNoRequest` asserts `outcomeMessage == "Google export not configured."` (the literal) and zero stub HTTP requests; `exportShowsOutcome` compares against the literal "Exported. The Google Doc is up to date.".

## Acceptance criteria
1. `HighlightsBrowserModelTests/exportSelectionIgnoresASecondCall`: stub export held open; calling `exportSelection()` twice concurrently → the stub saw one call; `isExporting` true while held, false after.
2. `ExportTargetsModelTests/exportNowIgnoresASecondCallForTheSameTarget`: same pattern for `exportNow(id)`; a different id is not blocked.
3. `ExportSheetModelTests/scopeWithoutTargetResetsOptions`: scope A has a target with non-default options; switch to scope B with no target, `prefillOptions()` → `options == ExportOptions()`.
4. The three tightened `ExportSheetModelTests` above pass and each fails if its assertion is reverted (state which assertion catches what in the report).
5. `GoogleSignInAuthTests/accountModelHasLoadedAfterRefresh`: false initially, true after `refresh()` with a configured stub auth; `state` is `.signedOut` (not `.notConfigured`) after refresh with a configured stub.
6. `HighlightsBrowserModelTests/thumbnailsArePrunedWithTheList`: an image highlight listed, then deleted → its path is no longer in `thumbnails` after the next emission (bounded wait).
7. `./scripts/test.sh StudyReaderTests/HighlightsBrowserModelTests StudyReaderTests/ExportSheetModelTests StudyReaderTests/ExportTargetsModelTests StudyReaderTests/GoogleSignInAuthTests` passes; `./scripts/build.sh` succeeds.
8. VISUAL_CHECKS.md "Needs a Mac" gets one T83 row: filter bar at 900 pt and full width with a colour and a date filter on (no truncation, Sort picker doesn't move); Settings opens with no label selected; Settings > Google in a configured build shows a spinner then the signed-in/out state, never "not configured".

## Out of scope
The sign-in restore refresh (B32, Mac first), a draggable list/detail divider (B28 1, dropped), new XCUITests (T84 and the B17 decision), the export service and scheduler (T80).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer ui-builder Sonnet medium, reviewer code-reviewer Sonnet medium: CHANGES REQUESTED (1st), CI green (run 40690997136, 681 tests); missing test that a different target is not blocked while one export is in flight (acceptance criterion 2)
2026-10-28, implementer ui-builder Sonnet high (rework after 1st rejection; reworks: high), reviewer code-reviewer Sonnet high: APPROVED, CI green (run 40692222844, 682 tests); missing different-target test added (exportNowDoesNotBlockADifferentTarget); minor: Settings first-responder fix may need a later pass, check on the Mac (VISUAL_CHECKS T83 row)
