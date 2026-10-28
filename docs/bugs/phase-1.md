# Phase 1 bug hunt

- Date: 2026-10-28
- Scope: the whole app on `master` at `5ec2125` (Phase 1 T29–T90, the backlog pass T76–T90, the closing UI run and the fresh-clone check done). I read every file under `StudyReader/` except the pure SwiftUI layout views (library cards, settings forms, find bar, tag views). For those I only checked the async and state paths.
- Method: reading only. This was a cloud session on Linux with no Xcode, so no CI job and no `xcodebuild`. SQLite behaviour was checked with `python3 -I` sqlite3 (3.45.1) in the scratchpad. GRDB sources aren't checked out here, so every GRDB claim below comes from the code shape and the Phase 0 notes.
- Baseline: the latest CI runs are green (unit `40738460679`, fresh-clone `40739072211`).
- Schema: no new migration since `v2` (`git log` on SchemaV1/V2 and the goldens shows only T19). The frozen-migration rule still holds. The Phase 0 hazard patterns were grepped again and are not repeated: no untargeted `upsert`, no bare `Date` query arguments, no full-record `update(db)`.
- Spaced repetition: none in Phase 1 (Phase 2), so nothing to check there.

**Counts: critical 0, high 2, medium 5, low 10.**

| ID | Severity | Confidence | Title |
|---|---|---|---|
| H1 | high | CONFIRMED (code) | ⌘Z after annotating an auto-highlight deletes the highlight together with its note and tags |
| H2 | high | PLAUSIBLE (Google behaviour) | With an export folder set in Settings, every new Doc export fails under the `drive.file` scope |
| M1 | medium | CONFIRMED (code) | Every Drive 403 counts as "Doc missing", so a full Drive or a rate limit leads the user to break the Gemini Notebook link |
| M2 | medium | CONFIRMED (code) | "Queued" exports that nothing ever retries: Export Selection offline, and manual exports while the network path reports satisfied |
| M3 | medium | CONFIRMED (code) | Export targets whose document, tag or category is deleted or merged fail forever with "Couldn't prepare the export." |
| M4 | medium | CONFIRMED (code) | Quitting within the 500 ms autosave window loses the last note edits (no save on quit) |
| M5 | medium | CONFIRMED (code), click needs a Mac check | Links from imported Markdown skip the reader's http/https/mailto filter in the popover, panel, browser and detail pane |
| L1 | low | CONFIRMED | Every note save re-adds all `#tags` in the note, which undoes tag deletes and merges and tag-field removals |
| L2 | low | PLAUSIBLE (timing) | Tag field and note editors read, then write in separate transactions (lost updates) |
| L3 | low | CONFIRMED (code) | Deleting a document leaves its open reader tab working on a deleted row |
| L4 | low | CONFIRMED (code) | A password or large-file prompt for a Dock or Open With import while the library window is closed blocks every later import |
| L5 | low | CONFIRMED (sqlite) | The "With note" filter counts newline-only notes, because SQL `TRIM` strips spaces only |
| L6 | low | CONFIRMED (sqlite) | Tag names are unique only for ASCII case (`Über`/`über`), and the export merges such tags into one section |
| L7 | low | CONFIRMED (CommonMark) | Note headings inside a list item or quote (`- # of samples`) still become H1 in the export |
| L8 | low | CONFIRMED (code) | Tag names, and titles or authors with line breaks (PDF metadata), break the export structure (extends B29) |
| L9 | low | CONFIRMED (code) | Changing a colour label never triggers Keep in sync |
| L10 | low | CONFIRMED (code) | Each reader tab watches its metadata through the whole-library query, re-run on every highlight or tag write |

---

## High

### H1. ⌘Z after annotating an auto-highlight deletes the highlight together with its note and tags
- **Severity:** high. The user's own note text is lost for good: Redo does nothing, there's no confirmation, and it's one standard shortcut away in the default setup (auto-highlight on).
- **Confidence:** CONFIRMED by reading the code end to end. The menu path itself needs a Mac check.
- **Location:**
  - `StudyReader/Features/Reader/ReaderModel.swift:156-170`: `reconcileAutoHighlightMark` drops the undo mark only when the row is deleted or recoloured.
  - `StudyReader/Features/Annotations/NoteEditorModel.swift:111-116`: the highlight note goes straight to `HighlightRepository.updateNote`, not through `HighlightService`.
  - `StudyReader/Features/Annotations/Tags/TagFieldModel.swift:191-198`: tags go straight to `TagRepository`.
  - `StudyReader/Features/Annotations/HighlightService.swift:44-45, 129-134`: `lastAutoHighlightId` is forgotten only by service calls.
  - `StudyReader/App/AppCommands.swift:171-185`: the Undo path.
  - `StudyReader/Features/Reader/PDF/PDFHighlightController.swift:228-237` and `Text/TextHighlightController.swift:135-144`: the registered undo action.
- **Scenario:**
  1. Auto-highlight is on. Select a sentence in a PDF or Markdown reader, so a highlight is created.
  2. Click the highlight, type a note ("exam: derive this"), add the tag "exam", close the popover.
  3. Press ⌘Z in the reader, for example to undo a typo in the note. Edit > Undo still reads "Undo Highlight".
  4. Result: the highlight row is deleted with its note and tag links. Redo sends `redo:` and nothing comes back.
- **Why it is real:**
  - Neither the note save nor the tag change touches the service, so the service still remembers the id.
  - `canUndoHighlight` stays true because the live row keeps the colour of the mark.
  - `performUndo()` runs the window's undo manager, whose top action calls `model.undoLastAutoHighlight()`, then `highlightService.undoAutoHighlight(id:)`, which deletes the row.
- **Failing test (ReaderModel or HighlightService suite):**
  1. `createHighlight(new, isAuto: true)`.
  2. `HighlightRepository.updateNote(id:note:"x"…)`.
  3. Wait for `observeHighlights` to list the new note.
  4. Expect `canUndoHighlight == false`, and expect `undoLastAutoHighlight()` to leave the row in place. Today `canUndoHighlight` stays true and the row is deleted.
- **Fix direction:** make any edit of the highlight end its undo window. For example, `reconcileAutoHighlightMark` also clears the mark when the live row's `note` or `updatedAt` differs from the created row. Or route note and tag saves through `HighlightService` so they call `forgetAutoHighlight()`. Add the test above.
- **Owner:** pdf-engine (ReaderModel and controllers), with data-layer if the service gets the note path.

### H2. With an export folder set in Settings, every new Doc export fails under the `drive.file` scope
- **Severity:** high if confirmed. SPEC F-21 offers "a folder chosen once in Settings (by pasting a folder link)". With a folder set, every first export, every Create New Doc and every Export Selection fails with "Google Drive refused the upload." Nothing in the message points at the folder.
- **Confidence:** PLAUSIBLE. The code path is confirmed. The failure depends on Google's per-file authorization, which I couldn't run here.
  - `drive.file` only grants access to files the app created or that the user opened with the app (Picker).
  - A folder the user made in the Drive web UI and pasted as a link is neither, so `files.create` with that folder in `parents` is expected to answer 404 "File not found: <folderId>" (sometimes 403).
  - The planned Mac end-to-end check (VISUAL_CHECKS T73 row, "a Doc appears in the folder") would show it at once.
- **Location:**
  - `StudyReader/Features/Export/ExportTargetsModel.swift:34-49`: stores any pasted folder ID.
  - `StudyReader/Features/Export/GoogleExportService.swift:122` (`folderId` for a create), `:163` (new target takes `settingsFolderId`), `:187-193` (Export Selection), `:275-276` (a 403/404 on create becomes `.failed("Google Drive refused the upload.")`).
  - `StudyReader/Features/Export/DriveUploadRequest.swift:41`: `parents: [folderId]`.
  - SPEC F-21 (docs/SPEC.md:379) and ARCHITECTURE §9.2 combine the pasted folder with `drive.file`.
- **Reproduction (Mac, real Google account):**
  1. In the Drive web UI, create a folder and copy its link.
  2. Paste the link into Settings > Google and click Save.
  3. Export one document. Expected: a Doc in that folder. Likely: "Google Drive refused the upload." and no Doc.
  4. Clear the folder field: the same export works.
- **Fix direction:** first confirm with one real request. If confirmed, this is a spec decision:
  - (a) Let the app create its own "StudyReader" folder (app-created, so `drive.file` can use it) instead of pasting a link.
  - (b) Or keep the field, but on a 404/403 for the parent, say "StudyReader can't use this folder with its limited Google access", and don't save the target's `googleFolderId`.
- **Owner:** architect (SPEC F-21 / ADR-0007 decision), then integrations.

---

## Medium

### M1. Every Drive 403 counts as "Doc missing", so a full Drive or a rate limit leads the user to break the Gemini Notebook link
- **Severity:** medium. The content isn't lost, but the app's "Create New Doc" advice destroys the one thing F-21 protects: the same file ID that Gemini Notebook auto-syncs.
- **Confidence:** CONFIRMED in the code. The Drive side is documented behaviour:
  - Drive answers 403 for `storageQuotaExceeded`, `userRateLimitExceeded`, `rateLimitExceeded` and `dailyLimitExceeded`, as well as for a lost permission.
  - Since 2021, an account over its storage quota can't edit Google Docs.
- **Location:** `StudyReader/Features/Export/GoogleExportService.swift:346-347` (`case 403, 404: return .denied`, status only, body never read) and `:275-276` (`.denied` on update becomes `.docMissing`). The "Create New Doc" actions that clear the ID are `ExportSheetModel.swift:102-108` and `ExportTargetsModel.swift:58-64, 76-78`. ARCHITECTURE §9.2 (docs/ARCHITECTURE.md:489) prescribes "403/404 on update → Doc missing", while SPEC F-21 says "rate limit (retry with backoff, max 3)".
- **Scenario:**
  1. A free Google account fills its 15 GB.
  2. Keep in sync updates the target, Drive answers 403 `storageQuotaExceeded`, and the app shows "Doc missing: The Google Doc was deleted or you lost access."
  3. The user clicks Create New Doc. `clearFileId` forgets the linked ID, and the create fails too ("Google Drive refused the upload.").
  4. After storage is freed, the next export creates a new Doc. The Notebook source (the old Doc) never updates again.
  - A 403 rate-limit answer goes the same way instead of being retried with backoff.
- **Failing test:** stub `HTTPClient` → PATCH answers 403 with body `{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}`. Expect a failed outcome ("Google Drive storage is full") and an unchanged `googleFileId`. Today the outcome is `.docMissing`. With reason `userRateLimitExceeded`, expect the 1/4/16 s backoff (three sleeper calls). Today nothing is retried.
- **Fix direction:** decode `error.errors[0].reason` on 403:
  - `rateLimitExceeded`, `userRateLimitExceeded` → the 429 backoff path;
  - `storageQuotaExceeded` → `.failed` with a clear text;
  - only `notFound`, `appNotAuthorizedToFile`, `insufficientFilePermissions` (and 404) → `.docMissing`.
  - Amend ARCHITECTURE §9.2.
- **Owner:** integrations (architect for the §9.2 wording).

### M2. "Queued" exports that nothing ever retries: Export Selection offline, and manual exports while the network path reports satisfied
- **Severity:** medium. The user is told an export will happen and it never does (SPEC F-21: "offline (queue and retry when online)").
- **Confidence:** CONFIRMED in the code. The trigger in case (b) is plausible: DNS failure, a captive portal or VPN, or a connection dropped mid-upload.
- **Location:**
  - (a) `StudyReader/Features/Export/GoogleExportService.swift:176-201`: `exportSelection` saves no target (ADR-0018) but returns `.queued` when offline. `HighlightsBrowserModel.swift:77-86` shows `ExportSheetModel.message(for: .queued)` = "You're offline. The export will run when you're back online." (`ExportSheetModel.swift:116`).
  - (b) `StudyReader/Features/Export/ExportSyncScheduler.swift:127-144`: the "queued while the path is satisfied" retry (B34 2, T80) only covers outcomes of the scheduler's own `syncNow`. `:190-215`: `retryQueued` runs only when the path changes from unsatisfied to satisfied. `GoogleExportService.isOffline` (`:477-485`) also maps `.cannotFindHost`, `.networkConnectionLost` and `.dataNotAllowed`, which happen while NWPathMonitor says satisfied.
- **Scenario:**
  - (a) Wi-Fi off, select 3 highlights, Export Selection…. The alert says the export will run later. Wi-Fi on: nothing happens. No target exists, so nothing can run.
  - (b) On a captive-portal Wi-Fi, Export now gets `cannotFindHost`, so the target shows "Waiting for network". The path never changes from satisfied, so the target waits until the next network change or a relaunch.
- **Failing test:**
  - (a) `GoogleExportServiceTests`: transport `URLError(.notConnectedToInternet)` on `exportSelection`. The outcome/message must not promise a later run. Today it does.
  - (b) `ExportSyncSchedulerTests`: path stays satisfied; the target's `lastStatus` is set to `queued` outside the scheduler; advance the sleeper 60 s. Expect one export. Today there are none.
- **Fix direction:**
  - (a) Give Export Selection its own "couldn't reach Google Drive, try again" text, never the queued one.
  - (b) Let the scheduler pick up `queued` targets on a slow timer while the path is satisfied. Or have the manual export paths tell the scheduler (`scheduleRetry(targetId:)`) when they end `.queued`.
- **Owner:** integrations (ui-builder for the alert text).

### M3. Export targets whose document, tag or category is deleted or merged fail forever with "Couldn't prepare the export."
- **Severity:** medium. A Keep-in-sync Notebook source stops updating with a status that doesn't say why, and merging duplicate tags, a normal tidy-up, triggers it. The caller asked about "delete document with … export targets": they are not covered by any cascade.
- **Confidence:** CONFIRMED in the code.
- **Location:**
  - `StudyReader/Core/Repositories/ExportRepository.swift:192-217`: `scopeName` throws `notFound` for a missing document, tag or category.
  - `StudyReader/Features/Export/GoogleExportService.swift:114-120`: → `.failed("Couldn't prepare the export.")`.
  - `StudyReader/Core/Repositories/TagRepository.swift:113-138`: `merge` deletes the source tag and leaves its targets alone.
  - `StudyReader/Core/Repositories/DocumentRepository.swift:83-89` and `CategoryRepository.swift:95-107`: delete leaves the targets in place. The scope is JSON, so there is no foreign key.
  - `ExportSyncScheduler.swift:181-188, 127-144`: each later change starts the failed export again, plus three retries.
- **Scenario:**
  1. The user exports tag "#exam" with Keep in sync on and adds the Doc to Gemini Notebook.
  2. Later they merge "#exam" into "#exams" in the tag manager.
  3. Every change from then on runs the export, which fails without a network call. Settings > Google shows "Failed: Couldn't prepare the export.", and the Notebook source is frozen.
  - The same happens after deleting the exported document or a custom category.
- **Failing test (`TagRepositoryTests` or `ExportRepositoryTests`):**
  1. Insert a target with scope `.tag(source)`.
  2. `merge(sourceId: source, into: target)`.
  3. Expect the target scope to become `.tag(target)`. Today `scopeName(for:)` throws.
- **Fix direction:**
  - Merge moves tag-scoped targets to the surviving tag in the same transaction.
  - Deleting a document, tag or category either removes its targets or marks them with a clear status ("The exported tag no longer exists") and turns Keep in sync off.
  - Never delete the Doc.
- **Owner:** data-layer (repositories), integrations (status text).

### M4. Quitting within the 500 ms autosave window loses the last note edits (no save on quit)
- **Severity:** medium. A silent lost write of user-typed text (SPEC F-09 AC1: "Notes autosave and survive restart").
- **Confidence:** CONFIRMED in the code: no termination hook exists.
- **Location:**
  - `StudyReader/Features/Annotations/NoteEditorModel.swift:13, 75-84`: the save runs only 500 ms after the last keystroke.
  - Flushes are only in `onDisappear` as unstructured `Task`s: `DocumentNotePanelView.swift:28-31`, `HighlightPopoverView.swift:63-67`, `HighlightDetailView.swift:65-68`.
  - `StudyReader/App/AppDelegate.swift`: no `applicationShouldTerminate` / `willTerminate`.
  - The reading position has the same gap (`ReaderModel.swift:14, 227-231`, 1 s).
- **Reproduction (Mac):**
  1. Open a document's Notes tab and type a sentence without pausing.
  2. Press ⌘Q at once and relaunch.
  3. The text typed since the last 0.5 s pause is missing.
  - On ⌘Q, AppKit ends the run loop without waiting for the `Task { await note.flush() }` that SwiftUI might start.
- **Fix direction:** keep a registry of live `NoteEditorModel`s (or flush through `AppSession`). In `applicationShouldTerminate`, answer `.terminateLater`, await all flushes (and `ReaderModel.flushPosition`), then `reply(toApplicationShouldTerminate: true)`.
- **Owner:** ui-builder.

### M5. Links from imported Markdown skip the reader's http/https/mailto filter in the popover, panel, browser and detail pane
- **Severity:** medium (security hardening). The reader blocks every other link scheme on purpose (`TextReaderView.openableLinkSchemes`; B8 is about its context menu). A highlight copies the link into `richText`, and four other views make that link clickable with no filter.
- **Confidence:** CONFIRMED that the stored text keeps any scheme and is rendered as a SwiftUI link. That a click opens it is the standard `Text` + `OpenURLAction` behaviour. Try it once on a Mac (the popover and detail pane aren't Lists, so their links are certainly clickable).
- **Location:**
  - `StudyReader/Features/Reader/Text/TextReaderView.swift:17-18, 181-197`: the filter.
  - `StudyReader/Features/Reader/Markdown/MarkdownRenderer.swift:374-381`: any URL that parses becomes a link.
  - `StudyReader/Features/Annotations/RichTextMarkdown.swift:57-63, 122-131`: the destination is stored in `richText`.
  - `StudyReader/Features/Annotations/RichTextView.swift:12-16`: `AttributedString(markdown:)` → `Text`, no `openURL` override.
  - Used in `HighlightPopoverView.swift:79`, `HighlightDetailView.swift:80`, `HighlightsBrowserView.swift:475`, `HighlightsPanelView.swift:146`. Notes, rendered by `NoteMarkdown.swift:126-129`, have the same gap for pasted text.
- **Reproduction (Mac):**
  1. Import a `.md` file that contains `[lecture slides](smb://example.invalid/share)` or `[open](file:///System/Applications/Calculator.app)`.
  2. In the reader, clicking it does nothing (correct).
  3. Highlight the sentence, open its popover (or the browser detail pane) and click the link: Finder's connect dialog appears, or Calculator launches.
- **Fix direction:** put `.environment(\.openURL, OpenURLAction { url in TextReaderView.isOpenable(url) ? .systemAction : .discarded })` around `RichTextView` and `NoteMarkdownView` (one shared helper), or drop non-openable links when building `richText`. Add a unit test for the filter helper.
- **Owner:** ui-builder.

---

## Low

### L1. Every note save re-adds all `#tags` in the note, which undoes tag deletes and merges and tag-field removals
- **Location:**
  - `StudyReader/Features/Annotations/NoteEditorModel.swift:102-118`: `write` parses the whole body and adds every tag on each save.
  - `TagRepository.swift:113-145`: merge and delete.
- **Scenario:**
  1. A note contains "#exam". The user deletes tag "exam" in the tag manager (or merges it into "exams", or removes the chip in the tag field).
  2. The user fixes a typo anywhere in that note.
  3. "exam" is created again and linked again.
  - SPEC F-10 only says that typing `#tagname` adds the tag.
- **Failing test (`NotesRepositoryTests` style):**
  1. Save the note "#exam".
  2. `delete(id:)` the tag.
  3. Change the note to "#exam x" and save.
  4. Expect no tag "exam". Today it exists again.
- **Fix:** add only the names in `hashTags(new) − hashTags(savedText)` (case-insensitive).
- **Owner:** ui-builder.

### L2. Tag field and note editors read, then write in separate transactions (lost updates)
- **Location:**
  - `StudyReader/Features/Annotations/Tags/TagFieldModel.swift:86-112, 191-198`: reads the assigned tags, then `setTags` deletes all links and inserts the list.
  - `NoteEditorModel.swift:50-66, 86-98`: loads the note once; the last save wins.
- **Scenario:**
  - (a) The note autosave adds `#exam` (`addTag`) between the tag field's read and its `setTags`, so "exam" is dropped.
  - (b) The same highlight's note is open in the popover (reader window) and in the browser detail pane (library window). Typing in one, then the other, silently overwrites the first.
  - Both need narrow timing or two windows.
- **Fix:** use the existing `addTag(_:toHighlights:)` / `removeTag(_:fromHighlights:)`, and add `removeTag(_:fromDocuments:)`, instead of `setTags`. Optionally compare `updatedAt` before saving a note.
- **Owner:** ui-builder, data-layer.

### L3. Deleting a document leaves its open reader tab working on a deleted row
- **Location:**
  - `StudyReader/Features/Library/LibraryModel.swift:128-136` and `LibraryView.swift:314-320`: no tab is closed.
  - `ReaderModel.swift:113-122`: a missing row is skipped silently.
  - `HighlightService.swift:94-99`: a snapshot creates `Documents/<id>/snapshots/` again before the insert fails.
- **Scenario:**
  1. Open a PDF, then delete it from the library.
  2. The tab keeps showing it. New highlights give "The highlight couldn't be saved.", Notes-tab typing shows an error, and position saves log `notFound`.
  3. A snapshot leaves an orphan folder until the next launch.
- **Fix:** have the delete close the document's reader tab (or set the model to `.failed("This document is no longer in the library.")`, triggered by the observation when the row disappears).
- **Owner:** ui-builder.

### L4. A password or large-file prompt for a Dock or Open With import while the library window is closed blocks every later import
- **Location:**
  - `StudyReader/App/RootView.swift:81, 86-91`: the prompts and the URL handler live in the library window.
  - `ExternalURLRouter.swift:3-5`: the handler stays attached after the window closes.
  - `ImportCoordinator.swift:60-71, 105-117`: batches run one after another, and the continuation waits for an answer.
- **Scenario:**
  1. Close the Library tab (⌘W) while a reader tab is open.
  2. Drop a locked PDF on the Dock icon. `passwordRequest` is set, but no view shows the sheet.
  3. That batch, and every later Dock or Open With batch, waits until the user happens to reopen the library window. Nothing is visible meanwhile (B1 covers only the quiet success case).
- **Fix:** bring the library window forward (`openWindow(id: "main")`) when a prompt is requested, or show the prompts window-independently.
- **Owner:** ui-builder.

### L5. The "With note" filter counts newline-only notes, because SQL `TRIM` strips spaces only
- **Location:** `StudyReader/Core/Repositories/HighlightBrowseQuery.swift:147-149` (doc comment at `:12`: "has text after trimming").
- **Reproduction (checked with SQLite 3.45.1):** `TRIM('\n') <> ''` is 1, and so is `TRIM(' \n\t ')`. A note left as one Return shows under "With note" with an empty preview, while the export treats it as no note (`ExportRepository` trims in Swift).
- **Fix:** `TRIM(h.note, ' ' || char(9) || char(10) || char(13))`, or trim on save.
- **Owner:** data-layer.

### L6. Tag names are unique only for ASCII case (`Über`/`über`), and the export merges such tags into one section
- **Location:**
  - `StudyReader/Core/Repositories/TagRepository.swift:251-254` (lookup via `COLLATE NOCASE`).
  - `ExportRenderer.swift:106-108` (sections keyed by Swift `lowercased()`).
  - `TagFieldModel.swift:116-132` (suggestions use Swift case folding).
- **Reproduction (checked with SQLite):** after inserting `Über`, inserting `über` succeeds, so NOCASE folds ASCII only. SPEC F-10 AC1 says "case-insensitively unique".
- **Fix:** compare names folded in Swift (`lowercased()` or `.caseInsensitive` compare) before inserting and in rename.
- **Owner:** data-layer.

### L7. Note headings inside a list item or quote (`- # of samples`) still become H1 in the export
- **Location:** `StudyReader/Features/Export/ExportRenderer.swift:267-306`. The heading rule only looks at the first non-blank character of a line.
- **Scenario:**
  - A document note line `- # of samples: 30` is a list item whose content is an ATX heading in CommonMark. It is written unchanged, so Google Docs gets an H1 inside the list. The same goes for `> # Quote`.
  - A highlight-note continuation line `    - # x` does the same inside `- Note:`.
  - This is a fourth hole next to T87 holes (1)–(3) in BACKLOG. It breaks SPEC F-21 "headings are demoted below the export's own headings".
- **Fix:** apply the heading rule after any run of list or quote markers too. Needs the same spec amendment the T87 holes wait for.
- **Owner:** integrations, after the architect amends the spec.

### L8. Tag names, and titles or authors with line breaks (PDF metadata), break the export structure (extends B29)
- **Location:**
  - `StudyReader/Features/Export/ExportRenderer.swift:20, 73-75, 116, 128, 144, 174`: titles, authors and tag names go in raw.
  - `MetadataDefaults.swift:16-24`: only the ends are trimmed.
  - `GoogleExportService.swift:471-475`: the HTML fallback passes raw inline HTML through swift-markdown's `HTMLFormatter`.
- **What B29 doesn't cover:**
  - (a) **Tag names** (any 1–40 characters from the tag field) are not mentioned in B29 and are raw too: `#<b>x`, `#a*b*`.
  - (b) A **PDF metadata title** is untrusted and may contain a line break. `## Line1\nLine2` turns the rest into body text, and a second line starting with `#` or `-` adds structure.
  - (c) In HTML-fallback mode, an HTML title or tag goes into the Doc as markup.
- **Fix:** at least replace line breaks with spaces in titles and authors at import and in the renderer. Fold tag names into the B29 decision.
- **Owner:** user decision (B29), then integrations.

### L9. Changing a colour label never triggers Keep in sync
- **Location:** `StudyReader/Core/Repositories/ExportRepository.swift:355-366` (the change token reads DB tables only). Labels live in UserDefaults and are rendered by `GoogleExportService.colorLabels`.
- **Scenario:** rename "Key concept" to "Core idea" in Settings. Synced Docs keep the old label until some unrelated DB change.
- **Fix:** let `AppSettings.setLabel` ask the scheduler to run its change handling, or include the labels in the token.
- **Owner:** integrations.

### L10. Each reader tab watches its metadata through the whole-library query, re-run on every highlight or tag write
- **Location:** `StudyReader/Features/Reader/ReaderModel.swift:113-122` uses `DocumentRepository.observeItems()` (`DocumentRepository.swift:161-187`): every document, every category, a `GROUP BY` over all highlights, and every `documentTag`.
- **Effect:** with N tabs open, each highlight, tag or metadata write runs N full-library queries plus the library window's. That's fine at today's sizes but grows with the 500-document / 20,000-page target (SPEC §4). Position saves don't re-run it, because GRDB tracks the selected columns.
- **Fix:** add `observeItem(id:)` (one document plus its category name).
- **Owner:** data-layer.

---

## Known items re-confirmed (not re-reported)
- **B29**: titles and authors are raw in the export. Still undecided; L8 adds the tag-name and line-break cases.
- **T87 spec holes (1)–(3)**: code span across lines, setext underline, unclosed fence. Still present in `ExportMarkdownSafety.note` (L7 adds a fourth).
- **T90 follow-up, stale observation runs:**
  - `HighlightsBrowserModel.observe()` (`HighlightsBrowserModel.swift:95-112`) still assigns `items` and prunes `selection` without a generation or cancellation check. A real path exists but it is narrow: the old run must be suspended in `loadThumbnails` reading an uncached snapshot while a write emits and the filter changes. Then the old filter's rows overwrite the new list until the next change. Low.
  - `TagFieldModel`'s target is a `let`, so no cross-target overwrite is possible.
  - SearchModel (generation guard), HighlightPopoverModel (path guard), ReaderModel, TagManagerModel, CategoryManagerModel and ExportTargetsModel run one non-restarting observer each. No real path found.
- **T81 follow-up**: a failed undo has already cleared `lastAutoHighlightId` (`HighlightService.swift:130-132`). Still true.
- **B21 (3)** snippet cost, **B24** synchronous PDF find, **B38** position-restore versus reveal race in H9: Mac items, not re-checked.
- Phase 0 backlog **L2** (`inMemory(now:)` clock) and **L7** (FTS checks in three suites): still open, unchanged.

## Needs a Mac to settle
- H2: one real export with a pasted folder.
- M5: click the smb/file link in the popover.
- "Reveal Original in Finder" after a relaunch: the bookmark is created without `.withSecurityScope` (`ImportService.swift:193`) and the sandbox may refuse `fileExists` on the resolved path (`LibraryModel.swift:157-169`), so it may always say "no longer available". Not verified, so not a finding.

## Checked and found sound
- **Import:**
  - Batches are serialized by `ImportCoordinator`, so `ImportService`'s actor reentrancy across prompts can't race the hash lookup. A duplicate that does race is caught by the UNIQUE `fileHash` and reported as "Already in library".
  - The folder is removed on every failure after it is created, and the orphan sweep runs at launch before any import.
  - `.PDF` and `.MD` extensions are handled. Locked PDFs are hashed as the original and stored unlocked through `writeUnlockedCopy`, which refuses `destination == url`.
  - Folder depth 3 is honoured.
- **FileStore:** every builder validates canonical IDs and extensions, and `url(forRelativePath:)` rejects absolute paths, `.`/`..` and non-ID first components. Markdown image sources with `..` can only reach what the sandbox allows.
- **User's files:** the user's PDFs are never written. The only `PDFDocument.write` is the unlocked copy in the container, and annotations are in-memory only.
- **Data layer:**
  - Column-limited updates everywhere. FTS triggers are untouched since v2.
  - Document delete cascades (highlights, tag links, notes, review cards, embeddings) and then removes the folder.
  - Highlight delete removes snapshot files.
  - Category delete moves documents to Other in one transaction.
  - Tag merge skips existing links.
  - `upsertAndFetch` on `documentNote` targets the PK only.
  - Dates are bound as `databaseUnixSeconds`.
- **Search:** user text only reaches MATCH quoted (quotes doubled, NUL dropped, punctuation-only terms dropped). Column-scoped NOT matches the highlight/note split. Only `fts5:` errors are swallowed. All filters are bound arguments.
- **Browse SQL:** only fixed fragments are interpolated, every value is bound, and ties break on id.
- **Text anchoring:**
  - Prefix and suffix are widened to composed-character boundaries, so emoji and combining marks are never split.
  - The re-anchor window has bounds checks (`needle.count <= haystack.count`, lower bound > upper bound skips the window).
  - The whitespace-collapsing map clamps offsets. Empty or whitespace-only anchors become orphans.
  - The rendered string is identical in the reader and in extraction (same renderer, `.standard` style, front matter stripped), so section unit indexes match.
- **PDF anchors, snapshots and positions:**
  - Rects, annotation bounds, hit-testing and snapshots all use unrotated page space. The snapshot maps rotation to `draw(with:to:)` space and caps the bitmap (8192 px side, 16.7 MP).
  - The position key uses the crop-box origin consistently for text and image highlights.
  - Position restore waits for a laid-out window.
- **Export renderer:** `noteLines[0]` can't be empty (the note is trimmed and non-empty, and `note()` keeps every non-blank character). Highlight bodies are neutralised: line-start `#>-+=`, ordered markers, `<|~`, entities, images. A fence is impossible because backticks are escaped in plain text and the backtick-fence info-string rule covers code spans.
- **Drive requests:** the file ID is percent-encoded into the path, metadata is JSON-encoded, and the boundary avoids content. One gate per target serializes exports. `cancelled` writes nothing. 401 → one refresh → sign-in required. Tokens, emails and content are never logged (only `domain code` and status codes). OAuth redirects go only to `GIDSignIn.handle`, and only when configured.
- **Scheduler:** the change token excludes `exportTarget`, so recording a result doesn't loop. Position, progress and lastOpened writes don't touch the tracked columns. Each target is debounced. The failure retry count resets on success and on a new change.
- **Crash scan:** no `try!`, no `as!`, no force unwraps, and one `fatalError` (an unavailable `init(coder:)`). Every array index is guarded (`isBullet` ensures `count > 1`, `orderedListMarker` bounds, the `ExportRenderer` label index). Ordered-list start indexes are capped at 9 digits by cmark, so `Int(UInt)` can't trap.
- **Concurrency:**
  - Swift 6 strict concurrency holds. PDFKit off the main actor always opens its own `PDFDocument` (import inspection, extraction, cover, snapshot).
  - Debouncers drop superseded actions. `SearchModel` and `ExportSheetModel.prefillOptions` drop stale results.
  - `LibraryModel` has the T90 generation guard.
- **Debug menu:** `#if DEBUG` only.
