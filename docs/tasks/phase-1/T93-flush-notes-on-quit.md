# T93: Quitting never loses the last typed note text (flush pending writes on quit)

- **Phase:** 1 (bug hunt `docs/bugs/phase-1.md` M4; SPEC F-09 AC1 as amended 2026-10-28)
- **Agent:** ui-builder (app shell: `AppDelegate`, `AppLaunchModel`, `AppEnvironment`). Escalation (CLAUDE.md): Sonnet agent. 1st rejection → same agent, effort `high`, with the spec and the review report. 2nd rejection → stop and ask the user. Reviews after an escalation run code-reviewer with effort `high`.
- **Depends on:** T92b (order only); T91 (also edits `ReaderModel`)
- **ADRs:** ADR-0015 (debounced saves through `Sleeper`), ADR-0011 (launch)
- **Visual check needed:** yes (Mac row "T93" in VISUAL_CHECKS.md "Needs a Mac", added by the orchestrator from the report: type in the Notes tab, the popover and the browser detail pane, ⌘Q at once, relaunch → text kept)
- **UI tests:** none. Verify with `./scripts/build.sh` and unit-test filters only.

## Goal
`NoteEditorModel` saves 500 ms after the last keystroke. The only early saves are `onDisappear` flushes in unstructured `Task`s (`DocumentNotePanelView`, `HighlightPopoverView`, `HighlightDetailView`). On ⌘Q AppKit ends the run loop without waiting for them, and `AppDelegate` has no termination hook, so the text typed in the last half second is lost. The reading position (`ReaderModel`, 1 s debounce) has the same gap. Make quit wait for every pending note and position save.

## Decisions
- **Hook: `applicationShouldTerminate(_:)` returning `.terminateLater`**, then `NSApp.reply(toApplicationShouldTerminate: true)` after the flushes. Not `applicationWillTerminate` (it can't await) and not `scenePhase` (on macOS it doesn't reliably change before termination).
- **Registry, not view hooks.** Each `NoteEditorModel` and `ReaderModel` registers itself, weakly, in one `PendingWrites` object owned by `AppEnvironment`. Quit flushes every live one. Covered automatically: the reader's Notes tab, the highlight popover, the Highlights browser detail pane, and each reader tab's position, in every window.
- **Window close** keeps working as today: each `onDisappear` starts `Task { await note.flush() }`, and that task holds the model strongly, so the save completes after the view is gone while the app keeps running. If the window closes because the app quits, the quit flush covers it. No new window-close code. (A unit test pins "a flush started before the last reference goes away still saves".)
- **No timeout and no sleep.** The flushes are local database writes.
- **Deleted target while text is pending** (document deleted from the library, or the highlight deleted, while its note is still inside the debounce): the flush fails quietly. `saveDocumentNote` hits the `documentNote` → `document` foreign key, `updateNote` throws `notFound`; `NoteEditorModel.write` throws before adding any `#tag`, so no note row, tag or tag link is created. Quit continues; no alert.

## Files to touch
- `StudyReader/App/PendingWrites.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `let pendingWrites: PendingWrites`, created in `init`)
- `StudyReader/App/AppDelegate.swift` (modify: `applicationShouldTerminate`, static `terminationWrites`)
- `StudyReader/App/AppLaunchModel.swift` (modify: on success set `AppDelegate.terminationWrites = environment.pendingWrites`)
- `StudyReader/Features/Annotations/NoteEditorModel.swift` (modify: conform and register in `init`)
- `StudyReader/Features/Reader/ReaderModel.swift` (modify: conform and register in `init`)
- `StudyReaderTests/AppTests/PendingWritesTests.swift` (new)
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Interfaces to produce
```swift
/// Something with debounced writes that must land before the app quits.
@MainActor
protocol PendingWriteFlushing: AnyObject {
    /// Saves anything still waiting for its debounce, and returns when the write has finished (or failed).
    func flushPendingWrites() async
}

/// Weak registry of live writers (NoteEditorModel, ReaderModel). Owned by `AppEnvironment`; one per library.
@MainActor
final class PendingWrites {
    nonisolated init()                                   // AppEnvironment is built off the main actor
    /// Adds `writer` weakly. Registering the same object twice keeps one entry.
    func register(_ writer: any PendingWriteFlushing)
    /// Number of live (not yet deallocated) writers. Prunes dead entries.
    var liveCount: Int { get }
    /// Calls `flushPendingWrites()` on every live writer, one after another, and returns when all have finished.
    /// Writers registered or deallocated meanwhile are fine (a snapshot of the live ones is flushed).
    func flushAll() async
}

extension AppDelegate {
    /// Set by `AppLaunchModel.start()` when the library opens; nil before (quit then terminates at once).
    @MainActor static var terminationWrites: PendingWrites?
}
```
`NoteEditorModel.flushPendingWrites()` = `await flush()`. `ReaderModel.flushPendingWrites()` = `await flushPosition()`. Both call `environment.pendingWrites.register(self)` at the end of `init`.

## What to do
1. Add `PendingWrites` and the protocol. Store weak boxes (`struct WeakWriter { weak var value: (any PendingWriteFlushing)? }`) or an `NSHashTable.weakObjects()`; main-actor only.
2. `AppEnvironment` gets `let pendingWrites: PendingWrites` set to `PendingWrites()` in `init` (no new init parameter). It's a `Sendable` struct; a `@MainActor final class` is `Sendable`.
3. `AppDelegate.applicationShouldTerminate(_ sender:)`: if `terminationWrites` is nil or `liveCount == 0` → `.terminateNow`. Otherwise start `Task { @MainActor in await writes.flushAll(); sender.reply(toApplicationShouldTerminate: true) }` and return `.terminateLater`. Keep `application(_:open:)` exactly as it is (T74a/T90).
4. `AppLaunchModel.start()`: in the `.success` branch, right after creating the session, set `AppDelegate.terminationWrites = environment.pendingWrites`.
5. Register `NoteEditorModel` and `ReaderModel` as above. Don't change the views' `onDisappear` flushes.

## Acceptance criteria
1. `PendingWritesTests/flushAllSavesNoteTypedWithinTheDebounce`: environment built like the other suites do (`let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))`, then `AppEnvironment(fileStore: base.fileStore, database: base.database, now: base.now, settingsStore: TestSettings.make(), sleeper: ManualSleeper())`; remove the settings suite at the end) with a `ManualSleeper` (the debounce never fires on its own); a document and a highlight exist; a document-target and a highlight-target `NoteEditorModel` are loaded, `text` set (`"typed just before quit"`, `"#exam why"`); without advancing the sleeper, `await environment.pendingWrites.flushAll()` → `NotesRepository.documentNote(documentId:)?.body` and the highlight's `note` equal the typed texts, and tag "exam" is on the highlight.
2. `PendingWritesTests/flushAllSavesThePendingReadingPosition`: a `ReaderModel` (same environment) gets `textPositionChanged(offset: 120, textLength: 1000)`; `flushAll()` → the stored `textPosition` is 120.
3. `PendingWritesTests/registryIsWeak`: register two models, drop one → `liveCount == 1`; `flushAll()` with one deallocated writer completes.
4. `PendingWritesTests/registeringTwiceKeepsOneEntry`.
5. `PendingWritesTests/flushStartedBeforeTheViewGoesAwayStillSaves` (window-close path): a loaded `NoteEditorModel` with pending text; `let task = Task { await model.flush() }`, then the test's only reference is set to nil; `await task.value` → the text is stored.
6. `PendingWritesTests/flushAfterTheTargetIsDeletedCreatesNothing`: document-target model with pending text `"#ghost text"`; the document is deleted with `DocumentRepository.delete(id:fileStore:)`; `flushAll()` returns; no `documentNote` row for that id, no tag named "ghost", and `model.lastError != nil`. Same for a highlight target deleted with `HighlightRepository.delete(id:fileStore:)`: the highlight stays deleted, no tag "ghost". Ends with `FTSIntegrity.check`.
7. Existing `NotesRepositoryTests` (`autosaveAndRestore`, `hashTagsAddTagsOnSave`, …), `ReaderModelTests` and `AppLaunchModelTests` pass unchanged.
8. `./scripts/test.sh StudyReaderTests/PendingWritesTests StudyReaderTests/NotesRepositoryTests StudyReaderTests/ReaderModelTests StudyReaderTests/AppLaunchModelTests` passes; `./scripts/build.sh` succeeds.
9. Reviewer check: no `Task.sleep`/timer in the quit path; `application(_:open:)` unchanged; `reply(toApplicationShouldTerminate:)` is called exactly once on the `.terminateLater` path; no view's `onDisappear` flush removed.
10. Visual check (Mac, row "T93"): persistent library; type a sentence in the Notes tab and press ⌘Q without pausing, relaunch → the whole sentence is there; same for a highlight note in the popover and in the Highlights browser detail pane; scroll a PDF and ⌘Q at once → it reopens at the new position; quit with nothing open is instant.

## Out of scope
- L2 lost updates between two editors, L1 tag re-adding, L3 (open tab of a deleted document).
- Any change to the autosave delay or the debouncer.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer ui-builder Sonnet medium (no reworks), reviewer code-reviewer Sonnet medium: APPROVED, CI green (run 40754184897, 720 tests); no spec deviations; minor follow-up (second Cmd-Q starts a second flush and reply) in BACKLOG; Mac row T93 in VISUAL_CHECKS
