# T84: UI-test hygiene and a deterministic seed: fresh settings per in-memory launch, seed order and position keys, sturdier assertions

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` OB1 / B27 (4), B4, B23 (3), B27 (1), B28 (2)(3), B35 (1)(3), and the UI test for T83's B35 (2) fix)
- **Agent:** ui-builder
- **Depends on:** T83 (Settings focus fix), T82, T78 (last task of the backlog pass)
- **ADRs:** ADR-0011 (in-memory launches), ADR-0015 (amended 2026-10-28: the ephemeral suite is reset on an in-memory UI/exploratory launch)
- **Visual check needed:** no (UI tests)
- **UI tests:** YES, this task may run its own targeted UI tests (see criterion 9).

## Goal
Make UI-test launches independent of each other and of seeding order: every in-memory launch outside the unit-test host starts with default settings (the highlight colour no longer leaks between tests), the seed library gets real PDF position keys and distinct creation times (stable "Newest first" order and correct reading order), and the remaining weak or warning-producing UI-test spots are fixed.

## Files to touch
- `StudyReader/Core/Support/SettingsStore.swift` (modify: one static function)
- `StudyReader/App/AppLaunchModel.swift` (modify: `defaultFactory`)
- `StudyReader/Features/Debug/SampleLibrary.swift` (modify)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift`, `StudyReaderTests/LibraryTests/SampleLibraryTests.swift` (modify)
- `StudyReaderUITests/Support/StudyReaderUI.swift` (modify: add one helper; don't revert the user's earlier edits in `Support/`)
- `StudyReaderUITests/ExternalOpenTests.swift`, `LibraryOpenTests.swift`, `HighlightsBrowserTests.swift`, `TagManagerTests.swift`, `SettingsTests.swift` (modify)

## What to do
1. **OB1.** Add `static func resetEphemeral()` to `SettingsStore` (removes the persistent domain `ephemeralSuiteName`) and a pure `static func shouldResetEphemeralSettings(_ signals: AppEnvironment.TestHostSignals) -> Bool` on `AppLaunchModel`: true only when `inMemoryRequested` is true and `xctestEnvironment` is false (UI tests and `run-app.sh`, never the unit-test host). `defaultFactory` calls `resetEphemeral()` before `AppEnvironment.inMemory()` when it returns true.
2. **B27 1.** `SampleLibrary.highlight(for:in:now:)`, PDF case: `positionKey = PDFAnchorBuilder.positionKey(pageIndex: page, pageHeight: Double(sample.pageSize.height), topOfFirstRect: Double(lineRect(line, in: sample).maxY))`.
3. **B35 1.** Give seeded highlights distinct times: pass a running index (0, 1, 2 … in seeding order across all samples) and set `createdAt = updatedAt = now.addingTimeInterval(-Double(index))`, so "Newest first" lists them in seeding order on every launch.
4. **B4.** In `ExternalOpenTests`, the three "no alert" checks become `XCTAssertFalse(ui.alertButton("OK").waitForExistence(timeout: 2), …)` (a late alert can't slip past). Keep the messages.
5. **B23 3.** `LibraryOpenTests/testReturnInTheSearchFieldDoesNotOpenTheSelectedDocument`: after Return, assert `tabTitles.isEmpty` before `card(...).exists`.
6. **B28 2.** Add to `StudyReaderUI` a `func hasKeyboardFocus(_ element: XCUIElement) -> Bool` that reads `value(forKey: "hasKeyboardFocus")` only when `element.responds(to: NSSelectorFromString("hasKeyboardFocus"))`, else returns false. Use it in `HighlightsBrowserTests` (remove the private copy) and `LibraryOpenTests`.
7. **B28 3.** `HighlightsBrowserTests/testReturnAndEscapeStayInTheDetailPaneFields`: after Return in the (empty) Add Tag field, assert the field's value is still empty and no tag was created (the tag filter menu has no new entry). Read the test first: if it types text into the Add Tag field before Return, the T69 spec rule applies (Return adds the typed tag); then assert that and say so in the report.
8. **B35 3.** `TagManagerTests.tagRow(_:in:)`: mark it `@MainActor` (no isolation warnings left in the UI-test target).
9. **B35 2 test.** `SettingsTests/testSettingsOpensWithoutAFocusedLabelField`: open Settings (⌘,); no text field in the General tab has keyboard focus (`hasKeyboardFocus`); attach a screenshot.

## Acceptance criteria
1. `AppEnvironmentTests/resetsEphemeralSettingsOnlyForInMemoryLaunchesOutsideUnitTests`: `shouldResetEphemeralSettings` is true for `(xctestEnvironment: false, inMemoryRequested: true)`, false for `(true, true)`, `(false, false)`, `(true, false)`.
2. `SampleLibraryTests/seededPDFHighlightsUseRealPositionKeys`: after seeding, every PDF highlight's `positionKey` is ≥ `pageIndex * 1_000_000` and < `(pageIndex + 1) * 1_000_000`, and on one page a higher line has the smaller key.
3. `SampleLibraryTests/seededHighlightsHaveDistinctCreationTimes`: all seeded `createdAt` values are distinct; `browse(sort: .createdNewest)` lists them in seeding order.
4. No Swift 6 isolation warnings from `TagManagerTests.swift` in the UI-test compile (report the compile-warning lines from `build/ci/<run>/uitest.log`).
5. `HighlightsBrowserTests` and `LibraryOpenTests` use the shared `hasKeyboardFocus` helper; no other `value(forKey: "hasKeyboardFocus")` remains (reviewer Grep).
6. Unit tests: `./scripts/test.sh StudyReaderTests/AppEnvironmentTests StudyReaderTests/SampleLibraryTests StudyReaderTests/HighlightBrowseQueryTests` pass; `./scripts/build.sh` succeeds.
7. UI: `ReaderHighlightTests` (reading order, key 3, Undo) still pass with the new seed keys and fresh settings; their screenshots no longer show a pink toolbar button from an earlier test.
8. UI: `testSettingsOpensWithoutAFocusedLabelField` passes (it fails on the code before T83).
9. **This task may run its own targeted UI tests**, never two CI jobs at once, max 2 attempts: `./scripts/ci.sh uitest StudyReaderUITests/ExternalOpenTests StudyReaderUITests/LibraryOpenTests StudyReaderUITests/HighlightsBrowserTests StudyReaderUITests/TagManagerTests StudyReaderUITests/SettingsTests StudyReaderUITests/ReaderHighlightTests StudyReaderUITests/ExportSheetTests`. Report the run URL and the pass/fail list.

## Out of scope
New coverage from the T63/T69/T74 proposals (C-, S-, F-, H-series, unconfigured Google tab: B17 decision), an anchored `ReaderTabbingTests` variant (B3, dropped: `ReaderTabbing` keeps static state shared with the test host's own library window), product changes beyond items 1–3.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer ui-builder Sonnet medium, reviewer code-reviewer Sonnet medium: CHANGES REQUESTED (1st); B28(3) "no tag created" assertion (Add tag field count == 1) is vacuous: it holds with or without a created tag; must assert an unchanged count of tag chips/remove buttons/filter-menu tag entries (or drop it and say so). Minor: missing space at HighlightsBrowserTests.swift:109
2026-10-28, implementer ui-builder Sonnet high (rework after 1st rejection; reworks: high), reviewer code-reviewer Sonnet high: APPROVED; evidence: unit run 40697935931 (685 tests, same production code) + targeted UI run 40698878511 (HighlightsBrowserTests, 6 tests) green, UI log has no Swift compile warnings (rework only touched a UI test file, so no second full unit run); PDFAnchorBuilder.positionKey made nonisolated (needed by the nonisolated seed); minor follow-ups in BACKLOG
