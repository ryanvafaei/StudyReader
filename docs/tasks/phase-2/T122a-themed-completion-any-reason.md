# T122a: A themed review completes when its queue runs out, for any reason

- **Phase:** 2 (user decision 2026-10-29, amends T122 and ADR-0022)
- **Agent:** review-engine
- **Depends on:** T122
- **ADRs:** ADR-0022 (amended here)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 5.

## Decision
T122 made completion strict: only a queue emptied by successful ratings marked a themed review completed. The user decided (2026-10-29): **complete the review when its queue runs out for any reason (rated, deleted or suspended)**, consistent with Q6 (an empty selection counts as completed). Leaving the session early (`endSession()` with cards still in the queue) still never completes it. Skip never empties the queue.

## What to do
1. `ReviewSessionModel` (themed context): wherever the queue can become empty (after a rating, after a card is dropped because it was deleted or suspended, after a frequency change that suspends the last card, after `reloadCurrent()` drops a missing item), call `completeThemedReview(id:)` once and then finish, exactly as the rating path does today. Keep the daily path unchanged. Make sure completion happens exactly once per session (no double `markCompleted`), and completion errors still go to `errorMessage` while the summary shows.
2. Update `docs/decisions/0022-review-sessions-limits-and-keys.md` (the "A themed session is completed" bullet and a dated amendment line saying who decided and why) and the T122 spec (`docs/tasks/phase-2/T122-*.md`: the completion sentences in its Interfaces section, plus a line in its review log area that T122a amended it; do not rewrite the history of the existing review log lines).
3. Remove the T122 "OPEN QUESTION ... strict" item from `docs/BACKLOG.md` (keep the other T122 backlog item about pinning the calendar).

## Acceptance criteria
`@MainActor`, in-memory environment on `FixedNow`, a UTC calendar, end with `FTSIntegrity.check`; add to `StudyReaderTests/ReviewTests/ThemedSessionTests.swift` (or a new `ThemedCompletionTests.swift`):
1. `rateSomeThenLastIsDeletedCompletes`: three cards, rate two, the third card's highlight is deleted (`reloadCurrent()` or the next action drops it) → phase `.finished`, `lastCompletedAt` set once.
2. `rateSomeThenLastIsSuspendedCompletes`: rate one of two, then `setFrequency(.off)` on the last card → finished and completed.
3. `allCardsDroppedWithoutRatingCompletes`: both cards deleted or suspended before any rating → finished, completed, summary `reviewed == 0`.
4. `leavingEarlyStillDoesNotComplete` and the existing T122 themed tests pass unchanged (the strict-rule test names may need their expectations updated only where they asserted the old strict behaviour: say which).
5. `./scripts/test.sh StudyReaderTests/ThemedSessionTests StudyReaderTests/ReviewSessionModelTests StudyReaderTests/ReviewBadgeModelTests` passes (plus the new test file if you add one); `./scripts/build.sh` succeeds.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
