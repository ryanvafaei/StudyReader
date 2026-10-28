---
name: bug-patterns
description: Recurring StudyReader bug patterns found in end-of-phase hunts (phase 0, phase 0 second pass, phase 1); check each new phase for repeats
metadata:
  type: project
---

Reports: docs/bugs/phase-0.md (first pass), docs/bugs/phase-0-second-pass.md (after fixes T12–T25), docs/bugs/phase-1.md (2026-10-28, master 5ec2125: 0 critical, 2 high, 5 medium, 10 low). All first-pass findings were verified fixed in the second pass.

## Phase 0 patterns (still grep each phase; none repeated in Phase 1)
- **Untargeted upsert.** Check new repositories for `upsert(`/`upsertAndFetch(` without `onConflict:`.
- **Date as a query argument.** A bare `Date` binds as TEXT; compare `databaseUnixSeconds`. Phase 2: DailyReviewBuilder `dueAt ≤ now`, introducedToday, lastCompletedAt.
- **Frozen migrations.** Real library at v2; any schema change needs v3 + golden. Phase 1 added none.
- **FTS desync.** Use `update(db, columns:)`; tests should call `FTSIntegrity.check`.
- **Tokenizer scope** English-only (ADR-0014); don't report Persian.
- **Test-host safety**, unknown migrations, unindexed FK children, temp-dir leaks, Date `==` after a REAL round trip.

## Phase 1 patterns (new; look for them again in Phase 2/3)
- **Side doors around a service's state.** HighlightService forgets the ⌘Z auto-highlight only on its own calls, but note and tag edits go straight to repositories, so Undo later deletes an annotated highlight (H1). Whenever a service keeps "last X" state, check every write path that bypasses it. Phase 2: review/mastery edits vs. the passive card state.
- **Status-code-only HTTP error mapping.** Drive 403 means rate limit, quota and permission; mapping all to "Doc missing" leads users to break the Notebook link (M1). Check that integrations read the error reason.
- **Promises nothing keeps.** UI says "will run when back online" for paths with no retry owner (M2). For every `.queued`/pending outcome, find the code that resumes it.
- **JSON-scoped references without FK.** exportTarget.scope (document/tag/category/themedReview) isn't cascaded or retargeted on delete/merge (M3). Phase 2: themedReview.filter ids (tagIds, documentIds, categoryIds) will have the same hole.
- **Debounced saves with no quit flush.** 500 ms note / 1 s position autosave only flush in `onDisappear` Tasks; ⌘Q loses them (M4). New debounced writes need a termination flush.
- **Filters that live in one view only.** The reader filters link schemes; RichTextView/NoteMarkdownView render the same stored links with no filter (M5). When a safety rule is in one renderer, grep the other renderers.
- **Re-applying derived side effects on every save.** Note saves re-add every `#tag` (L1), undoing tag manager deletes/merges. Prefer diff against the last saved state.
- **Read-modify-write across two transactions** (TagFieldModel → setTags) loses concurrent adds (L2). Prefer the repository's add/remove methods.
- **SQLite text semantics:** `TRIM` strips spaces only; `COLLATE NOCASE` folds ASCII only (L5, L6). Verified with python sqlite3.
- **Window-bound prompts for app-level work.** Import prompts live in the library window; Dock/Open With imports with that window closed wait forever (L4).

**Why:** these are the hazards most likely to recur as Haiku/Sonnet implementers build on Phase 0/1 code.
**How to apply:** at each phase hunt, grep for these first (upsert, Date args, direct repository writes beside a stateful service, `case 403`, `.queued` messages, JSON id lists, `Debouncer(` without a quit flush, `AttributedString(markdown:)`/`text.link =`, `setTags(`, `TRIM(`, `NOCASE`), then do the category-based hunt.
