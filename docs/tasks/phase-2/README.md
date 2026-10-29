# Phase 2 — Review

> **Review log format (user rule, 2026-10-27).** Each line in a spec's "Review log": `date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason`. Approval counts only with green CI.

Epics (SPEC §6): E2.1 Scheduler (FSRS wrapper, F-19, F-17 card creation), E2.2 Daily review (F-15, F-18), E2.3 Mastery (F-16 manual cloze and Q&A), E2.4 Themed reviews (F-20), E2.5 Flashcards view (F-17 view).

Done when (SPEC §6): a daily review and a themed review run end to end with persisted FSRS scheduling.

Planned 2026-10-29 by the architect, in a cloud session. **Show the user the task list and the open questions (end of this file) before implementing.** T113 and T129 depend on answers (Q7, Q2); ADR-0022 is "Proposed" until Q1, Q3, Q5, Q6 and Q7 are answered.

New ADRs: [0021 review engine data conventions](../../decisions/0021-review-engine-data-conventions.md) (FSRS behind one file, our JSON, weights, suspension rule, cloze text, reschedule formula, no `v3`), [0022 review sessions, daily limits and review keys](../../decisions/0022-review-sessions-limits-and-keys.md). Amended: ARCHITECTURE §10.1–§10.3 (pointers to the ADRs; `defaultWv6` doesn't exist in swift-fsrs 5.0.0), DEPENDENCIES §2/§5 (same correction). For the user: `.claude/agents/review-engine.md` still names `FSRSDefaults.defaultWv6`; only the user can edit agent files.

## No schema change in Phase 2 (no `v3`)
Every Phase 2 feature fits the v2 schema: `reviewCard`, `reviewLog` and `themedReview` exist since v1. Review preferences live in `UserDefaults` (ADR-0015), cloze text in `reviewCard.answer` and suspension in the existing columns (ADR-0021). If an implementer finds a real need for a schema change, they report BLOCKED; the architect then plans one dedicated `v3` task (golden `Fixtures/schema/v3.sql`, upgrade test from `V1FixtureDatabase`, `registeredMigrationsInOrder` extended).

## Task order
Run in this order, one at a time (CLAUDE.md workflow). "Agent" shows a per-call model/effort override where the spec sets one. Size: XS < 1 h of work, S small, M medium (still 1–5 files).

| # | Task | Agent | Depends on | Size | Visual check |
|---|---|---|---|---|---|
| 1 | [T96 In-memory cleanup uses the wall clock](T96-in-memory-cleanup-wall-clock.md) (backlog L2) | ui-builder | none | XS | no |
| 2 | [T97 Stored FSRS card, ReviewScheduler, ReviewCardFactory](T97-fsrs-scheduler-wrapper.md) | review-engine (model sonnet, effort high) | T96 | M | no |
| 3 | [T98 FrequencyPolicy and ReviewDay](T98-frequency-policy-and-review-day.md) | review-engine | T97 (order) | S | no |
| 4 | [T99 ReviewCardRepository and ReviewSuspension](T99-review-card-repository.md) | data-layer | T97, T98 | M | no |
| 5 | [T100 New highlights get a passive review card](T100-passive-card-on-new-highlight.md) | data-layer | T99 | S | no |
| 6 | [T101 Category frequency and auto-create; suspension follows category changes](T101-category-frequency-and-suspension.md) | data-layer | T99 | M | no |
| 6a | [T129 One-time backfill of passive cards for older highlights](T129-backfill-passive-cards.md) (**only if Q2 = yes**) | data-layer | T100, T101 | S | yes (Mac row) |
| 7 | [T102 Rating writes, review log, daily queue query](T102-ratings-and-daily-queue.md) | data-layer | T99 | M | no |
| 8 | [T103 Card action writes: frequency override, edited text](T103-card-action-writes.md) | data-layer | T102 | S | no |
| 9 | [T104 DailyReviewBuilder](T104-daily-review-builder.md) | review-engine | T98, T102 | S | no |
| 10 | [T105 ReviewService](T105-review-service.md) | review-engine | T97, T103, T104 | M | no |
| 11 | [T106 Review settings and Settings > Review](T106-review-settings-tab.md) | ui-builder | T101, T104 | M | yes (Mac row) |
| 12 | [T107 ReviewCardContent and ClozeText](T107-review-card-content-and-cloze-text.md) | review-engine | T102 | S | no |
| 13 | [T108 ReviewSessionModel and ReviewBadgeModel](T108-review-session-model-and-badge.md) | review-engine | T105, T106, T107 | M | no |
| 14 | [T109 Review screen and sidebar badge](T109-review-screen-and-badge.md) | ui-builder | T108 | M | yes (Mac row) |
| 15 | [T110 Review actions bar](T110-review-actions-bar.md) | ui-builder | T109 | M | yes (Mac row) |
| 16 | [T111 Sample library seeds review cards](T111-sample-library-review-cards.md) | ui-builder | T99, T105 | S | no |
| 17 | [T112 UI tests part 1: daily review](T112-ui-tests-daily-review.md) (runs its own targeted UI class) | ui-builder | T106, T109, T110, T111 | M | no (these are the checks) |
| — | **Checkpoint R1** (below) | ui-tester | T112 | | |
| 18 | [T113 Daily review reminder](T113-review-reminder.md) (**only if Q7 = yes**) | ui-builder | T106, T112 (order) | S | yes (Mac row) |
| 19 | [T114 Mastery card writes](T114-mastery-card-writes.md) | data-layer | T99 | S | no |
| 20 | [T115 MasteryService](T115-mastery-service.md) | review-engine | T105, T107, T114 | M | no |
| 21 | [T116 Browse query: Mastery filter and card counts](T116-browser-mastery-filter-and-card-counts.md) | data-layer | T114 | S | no |
| 22 | [T117 Mastery editor sheet](T117-mastery-editor-sheet.md) | ui-builder | T115 | M | yes (Mac row) |
| 23 | [T118 Mastery in the Highlights browser; bulk Create Review Cards](T118-mastery-entry-points-and-bulk-cards.md) | ui-builder | T116, T117 | M | yes (Mac row) |
| 24 | [T119 Mastery in the reader popover](T119-mastery-in-the-reader-popover.md) | ui-builder | T117, T118 | S | yes (Mac row) |
| 25 | [T120 ThemedReviewRepository](T120-themed-review-repository.md) | data-layer | T102 | M | no |
| 26 | [T121 ThemedReviewBuilder and ThemedReviewSchedule](T121-themed-review-builder-and-schedule.md) | review-engine | T98, T120 | S | no |
| 27 | [T122 Themed sessions, completion, themed badge](T122-themed-sessions-and-badge.md) | review-engine | T108, T121 | M | no |
| 28 | [T123 Themed review editor sheet](T123-themed-review-editor-sheet.md) | ui-builder | T120 | M | yes (Mac row) |
| 29 | [T124 Themed Reviews section](T124-themed-reviews-section.md) | ui-builder | T109, T110, T122, T123 | M | yes (Mac row) |
| 30 | [T125 Flashcards query](T125-flashcards-query.md) | data-layer | T114 | M | no |
| 31 | [T126 FlashcardsModel](T126-flashcards-model.md) | review-engine | T105, T115, T125 | S | no |
| 32 | [T127 Flashcards view inside Review](T127-flashcards-view.md) | ui-builder | T109, T110, T117, T126 | M | yes (Mac row) |
| 33 | [T128 UI tests part 2: Mastery, themed reviews, flashcards](T128-ui-tests-mastery-themed-flashcards.md) (runs its own targeted UI classes) | ui-builder | T112, T118, T124, T127 | M | no (these are the checks) |
| — | **Checkpoint R2** (below) | ui-tester | T128 | | |
| — | End-of-phase backlog pass, fresh-clone check, bug hunt (below) | architect, test-runner, bug-hunter | R2 | | |

Task numbers continue after Phase 1's last task (T95; the wrap-up tasks were W1, W2). T129 is numbered last because it is conditional, but runs as row 6a. Tasks whose dependencies are met early (T107, T114, T120, T125) may run earlier if a chain is blocked; keep one implementer at a time.

## Visual checkpoints
CLAUDE.md "Per phase" step 3, with the Phase 2 checkpoints **R1** (after T112) and **R2** (after T128). The orchestrator adds both to VISUAL_CHECKS.md (it is outside `docs/`, so the architect doesn't edit it) and, after each task, the task's Mac row to "Needs a Mac" from its report.
- **Before each:** `./scripts/ci.sh status`; a failed master run is fixed first.
- **R1 (daily review end to end):** ui-tester runs the full UI suite in cloud mode (Phase 1 classes plus `ReviewSessionTests`) and reports in `docs/checkpoints/R1-cloud-<date>.md`. Checklist: SPEC F-15 AC2/AC3 flows, F-18 actions, F-19 settings, the ADR-0022 key rule, the HANDOFF Return/Escape rule; Mac rows of T106, T109, T110 (and T129 if built) go to "Needs a Mac" (looks, light/dark, restart persistence with a real library).
- **R2 (Mastery, themed, flashcards):** the same, with `MasteryEditorTests`, `ThemedReviewsTests`, `FlashcardsTests`; Mac rows of T113, T117–T119, T123, T124, T127. The SPEC §6 "done when" is checked here by the UI tests (daily: T112 tests 2–4; themed: T128 test 4) and, with a persistent library and a relaunch, by the user on the Mac (T109 row: SPEC F-15 AC3).
- Only spec FAILs become fix tasks (T1xx a/b/…, same loop). Everything else goes to `docs/BACKLOG.md` under a new "Phase 2" heading. Ask the user only about NEEDS HUMAN items.
- The user does the "Needs a Mac" list at the end of the project (decision 2026-10-29); nobody waits for it.

## End of phase
1. **Backlog pass** (like Phase 1 rows 47–55): after R2, the architect plans one fix pass over the Phase 2 section of `docs/BACKLOG.md` (reviewer minors, checkpoint UX items) plus the older items the user picks (Q8). Then those tasks run through the normal loop.
2. test-runner: `./scripts/check-fresh-clone.sh`.
3. bug-hunter: `docs/bugs/phase-2.md`. Critical and high findings become fix tasks; the rest go to the backlog (policy in `docs/bugs/backlog.md`).
4. Update `docs/HANDOFF.md` at each checkpoint and at the end.

## Points of care for the orchestrator
- **T97** runs as review-engine with model `sonnet`, effort `high` from the first call (it must read the swift-fsrs 5.0.0 source, see its Step 0). Treat it as escalated: code-reviewer effort `high`; two rejections → ask the user. If it reports BLOCKED because the library hides its default weights, ask the user (options: a different swift-fsrs version, or an explicit decision to copy the weights; never decide silently).
- **UI tests:** only T112 and T128 run XCUITests (their own targeted classes, max 2 attempts, never in parallel with another CI job). Every other task verifies with `./scripts/build.sh` and unit-test filters. The UI-test target isn't compiled by `build.sh`, so T112/T128 are the first to compile new UI tests.
- **Constraint (HANDOFF standing rule, Library Return/Escape).** Phase 2 adds text fields to the main window in T110 (note and edit editors), T117 (Mastery sheet from the browser), T123 (themed editor sheet), T124 (session editors) and T127 (flashcards editors). Each spec carries the Constraint note; T112 and T128 hold the UI tests that prove it. Review sections replace the detail column, so `LibraryView` is never mounted with them; reviewers reject any change that keeps it mounted.
- **Review keys (ADR-0022):** Space and 1–4 are handled only by the focused card through `.onKeyPress`. Reviewers reject `.keyboardShortcut` without modifiers anywhere in `Features/Review/`.
- **Settings in tests:** tests that change settings use their own `TestSettings.make()` suite, never the shared ephemeral one (T108 explains the setup).
- **Future clocks:** T96 must be committed before any test passes a future `FixedNow` to `AppEnvironment.inMemory(now:)`. The orchestrator removes L2 from `docs/bugs/backlog.md` (naming T96) after its commit.
- **Reviewers reject** (in addition to Phase 1's list: full `update(db)` for status saves, `upsert(`, a bare `Date` in SQL, `URLSession.shared`, `Date()` or `Task.sleep` in logic, PDFKit across actors, any EPUB mention): `import FSRS` outside `ReviewScheduler.swift` and its tests; an update of `suspended`/`suspendedReason` outside `ReviewSuspension`; FSRS dates stored without `.storageRounded`; rating or scheduling logic in a view.
- **Shared files, in order:** `AppEnvironment.swift` (T96, T99, T105, T115, T120, T122, T129), `AppSession.swift` (T108, T113, T127), `RootView.swift` (T109, T124), `ReviewCardRepository.swift` (T99, T102, T103, T114, T125, T129), `ReviewQueue.swift` (T102, T120), `HighlightRepository.swift` (T100, T103), `ReviewService.swift` (T105, T122), `ReviewSessionModel.swift` and `ReviewBadgeModel.swift` (T108, T122), `ReviewCardView.swift` (T109, T110), `ReviewSectionView.swift` (T109, T127), `SettingsStore.swift` (T106, T129), `ReviewSettingsView.swift` (T106, T113), `Localizable.xcstrings` (T109, T118, T124, T127; new strings without plurals are auto-extracted on a Mac build, BACKLOG B15 (1)), `StudyReaderUI+Review.swift` (T112, T128), `FrequencyPolicyTests` (T98, T101 extension), `ReviewBadgeModelTests.swift` (T108, T122).

## Shared interfaces (where they're defined)
| Name | Task |
|---|---|
| `AppEnvironment.inMemory(now:)` cleanup by wall clock | T96 |
| `StoredFSRSCard`, `StoredFSRSLog`, `ReviewRating` (Core/Models); `ReviewScheduler`, `ScheduledReview`, `ReviewSchedulerError`, `ReviewCardFactory` | T97 |
| `FrequencyPolicy` (Core/Models), `ReviewDay` (Core/Support) | T98 |
| `ReviewCardRepository` (fetch, cards/observeCards(forHighlight:), insertPassiveCards, insertAutomaticPassiveCard), `ReviewSuspension.recompute`, `ReviewCardError`, `AppEnvironment.reviewCardRepository` | T99 |
| `HighlightRepository.insert(_:tagIds:passiveCard:)` | T100 |
| `CategoryRepository.setFrequency(id:_:)`, `setAutoCreateCards(id:_:)` | T101 |
| `ReviewQueueEntry`, `ReviewDayActivity`, `DailyQueueSnapshot`, `ReviewCardItem`, `RatingWrite`, `ReviewQueueSQL`; `dailyQueue`, `observeDailyQueue`, `items(cardIds:)`, `item(cardId:)`, `recordRating`, `dueCount(before:)` | T102 |
| `RescheduledCard`, `ReviewCardRepository.updateFrequencyOverride`, `HighlightRepository.updateEditedText` | T103 |
| `DailyLimits`, `DailyReviewPlan`, `DailyReviewBuilder` | T104 |
| `ReviewSessionContext`, `RatingOutcome`, `ReviewServiceError`, `ReviewService`, `AppEnvironment.reviewService` | T105 |
| `SettingsStore.reviewDailyLimit/reviewNewPerDay/showFourRatingButtons/reviewReminderEnabled/reviewReminderMinutes`, `AppSettings.dailyLimits`, `ReviewSettingsModel` | T106 |
| `ClozeRange`, `ClozeText`, `ReviewCardContent` | T107 |
| `RatingButton`, `ReviewKeyAction`, `ReviewSummary`, `ReviewSessionModel`, `ReviewBadgeModel`, `AppSession.reviewBadge`, `AppSession.dailyReviewModel()` | T108 |
| `ReviewStrings`, `ReviewSessionView(model:session:onDone:)`, accessibility identifiers `review-*` | T109 |
| `ReviewEditDraft`, identifiers `review-action-*`, `review-note-editor`, `review-edit-*`, `review-show-original` | T110 |
| Seeded review states (8-card daily plan) | T111 |
| UI helpers `StudyReaderUI+Review.swift` | T112 |
| `ReminderNotificationCenter`, `SystemReminderNotificationCenter`, `ReviewReminderScheduler`, `AppSession.reminder` | T113 |
| `ReviewCardRepository.insertMasteryCards/updateMasteryCard/deleteMasteryCard`, `ReviewCardError.notMasteryCard/.highlightMismatch` | T114 |
| `MasteryDraft`, `MasteryError`, `MasteryService`, `AppEnvironment.masteryService` | T115 |
| `HighlightBrowserFilter.hasMastery`, `HighlightListItem.masteryCardCount/reviewCardCount` | T116 |
| `MasteryEditorModel`, `MasteryEditorSheet`, `ClozeSelectionTextView` | T117 |
| `HighlightsBrowserModel.masteryFilter/canCreateReviewCards/createReviewCards()/bulkMessage/masteryHighlightId` | T118 |
| `HighlightPopoverModel.masteryCardCount`, `ReaderModel.masteryHighlightId/showMastery(highlightId:)`, `HighlightPopoverView(…onMastery:)` | T119 |
| `ThemedReviewDraft`, `ThemedReviewError`, `ThemedQueueSnapshot`, `ThemedReviewRepository`, `AppEnvironment.themedReviewRepository` | T120 |
| `SeededRandom`, `ThemedReviewBuilder`, `ThemedReviewSchedule` | T121 |
| `ReviewService.themedPlan(reviewId:)/completeThemedReview(id:)`, `ReviewSessionModel.themedReviewName`, `ReviewBadgeModel.themedDueCount/observeThemed()` | T122 |
| `ThemedReviewEditorModel`, `ThemedReviewEditorSheet` | T123 |
| `ThemedReviewsModel`, `ThemedEditorRequest`, `ThemedReviewsView` | T124 |
| `FlashcardState`, `FlashcardFilter`, `FlashcardItem`, `FlashcardSQL`, `ReviewCardRepository.flashcards/observeFlashcards` | T125 |
| `FlashcardsModel` | T126 |
| `ReviewSectionMode`, `AppSession.reviewSectionMode`, `AppSession.flashcardsModel()`, `FlashcardsView` | T127 |
| `ReviewCardRepository.backfillPassiveCards`, `SettingsStore.passiveCardBackfillDone`, `LibraryMaintenance.backfillPassiveCardsOnce` | T129 |

## Module map after Phase 2
```
StudyReader/Core/Models/               + StoredFSRSCard (StoredFSRSCard, StoredFSRSLog, ReviewRating), FrequencyPolicy
StudyReader/Core/Support/              + ReviewDay
StudyReader/Core/Repositories/         + ReviewCardRepository, ReviewSuspension, ReviewQueue (ReviewQueueSQL), FlashcardQuery,
                                         ThemedReviewRepository; HighlightBrowseQuery (+ Mastery filter, card counts)
StudyReader/Features/Review/           ReviewSectionView, ReviewSessionView, ReviewCardView, ReviewSummaryView, ReviewActionsBar,
                                       ReviewEditDraft, ReviewStrings
StudyReader/Features/Review/Scheduling/ ReviewScheduler (only `import FSRS`), ReviewCardFactory
StudyReader/Features/Review/Sessions/  DailyReviewBuilder, ReviewService, ReviewCardContent, ReviewSessionModel, ReviewBadgeModel,
                                       ThemedReviewBuilder (+ ThemedReviewSchedule, SeededRandom)
StudyReader/Features/Review/Mastery/   ClozeText, MasteryService, MasteryEditorModel, MasteryEditorSheet, ClozeSelectionTextView
StudyReader/Features/Review/Themed/    ThemedReviewEditorModel/Sheet, ThemedReviewsModel/View
StudyReader/Features/Review/Flashcards/ FlashcardsModel, FlashcardsView
StudyReader/Features/Review/Reminder/  ReviewReminderScheduler (T113, if built)
StudyReader/Features/Settings/         + ReviewSettingsView
StudyReaderTests/ReviewTests/          scheduler, policy, day, builders, service, actions, session, badge, content, cloze, mastery,
                                       themed, flashcards suites; CoreTests/ + ReviewCardRepository, ReviewQueue, action writes,
                                       Mastery writes, ThemedReviewRepository, FlashcardQuery suites
StudyReaderUITests/                    + ReviewSessionTests, MasteryEditorTests, ThemedReviewsTests, FlashcardsTests,
                                       Support/StudyReaderUI+Review.swift
```

## Open questions (answer before T97 starts; the recommended answer is what the specs assume)
- **Q1 (ADR-0022, T104):** Is the daily limit (15) a budget per review day or per session? *Recommended: per review day.* A second daily session the same day only shows due cards up to what's left of the 15; new cards up to what's left of the 5.
- **Q2 (T129):** Your library already has highlights from Phase 1, made before review cards existed. Should they get passive cards once, honouring each category's settings? *Recommended: yes.* They enter the review at the new-per-day rate (5 a day), so there is no flood. If no, drop T129. Then only highlights made from now on, plus "Create Review Cards" in the browser, get cards.
- **Q3 (ADR-0022, T126, T127):** F-18 lists Forgot/Remembered as available "in the flashcards view" too. Should the Flashcards view offer rating (an ad-hoc review outside any session), and Skip? *Recommended: no.* It offers every other F-18 action; rating stays in daily and themed sessions, so the logs and limits stay meaningful.
- **Q4 (T110):** The frequency menu needs a way to remove a card's override again. *Recommended:* a first item "Category default (High)" next to Off/Low/Normal/High.
- **Q5 (ADR-0022, T104):** Do new cards first rated in a themed session count against the daily "new per day" limit? *Recommended: yes* ("at most N new per day" across the app).
- **Q6 (ADR-0022, T122):** A themed review whose filter matches no cards: opening it shows "No cards match this review". Does that count as completed, so its "Due" badge clears? *Recommended: yes.*
- **Q7 (T113):** Build the optional reminder notification in Phase 2? It would be a daily local notification with fixed text, off by default. *Recommended: yes.* It is part of F-15 and small. It can only be checked on a Mac. If no, skip T113 (or move it to Phase 3's E3.5 settings polish).
- **Q8 (end-of-phase backlog pass):** Phase 2 makes two Phase 1 backlog items more likely. B40: deleting a themed review leaves its export targets failing forever. B41: every note save re-adds the note's `#tags`, and the review screen's note editor reuses that code. Should the Phase 2 backlog pass include B40 and B41? *Recommended: yes, both;* the other B42–B51 items stay as they are.
- **Q9 (T120):** Themed-review tag filters match the highlight's own tags. That is how the Highlights browser and the export's tag scope already work. A document's tags don't count. Keep it that way? *Recommended: yes.* Matching document tags too would be a later, separate change to all three.

## Phase done when
- All tasks in the table (T113 and T129 per Q7/Q2) are approved and committed (`TNN: <title>`), and checkpoint fixes and the backlog-pass tasks too.
- R1 and R2 have no open spec FAIL; the full unit suite passes via test-runner; `./scripts/check-fresh-clone.sh` passes.
- bug-hunter has run (`docs/bugs/phase-2.md`) and its critical and high findings are fixed.
- The SPEC §6 flow works: a daily review and a themed review end to end, with the schedule kept across a relaunch. The relaunch part is in the Mac rows, which the user checks at the end of the project.
