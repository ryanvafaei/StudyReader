# ADR-0021: Review engine data conventions

- Status: Accepted (Phase 2 planning, 2026-10-29)
- Date: 2026-10-29

## Context
ADR-0006 picked swift-fsrs (FSRS-6, long-term scheduler). ARCHITECTURE §10.1 names `FSRSDefaults.defaultWv6`, but swift-fsrs 5.0.0 (the version first pinned) is FSRS-5, has no `defaultWv6` and its `defaultW` is internal (ui-builder memory, T01). Amended 2026-10-29 (user decision): the package is pinned to swift-fsrs main @ `4fbaf20184d62f82a9f44f343337c61a2c5483e9` (MIT), where FSRS-6 is public, until a tagged release ships it (ADR-0006). The v1 schema stores `reviewCard.fsrsCard` and `reviewLog.fsrsLog` as JSON strings without saying whose JSON. Phase 2 also needs one rule for when a card is suspended, where cloze text lives, and how "reschedule from the last review" (SPEC F-18) works.

## Decision
- **FSRS stays behind one file.** Only `Features/Review/Scheduling/ReviewScheduler.swift` (and its tests) `import FSRS`. Everything else uses our own Codable value types in `Core/Models/StoredFSRSCard.swift`: `StoredFSRSCard`, `StoredFSRSLog`, `ReviewRating`. The JSON in `fsrsCard`/`fsrsLog` is *our* shape (keys listed in the T97 spec, dates as Unix seconds), never the library's own encoding, so a library upgrade can't break stored rows. Missing keys decode as defaults (the `"{}"` placeholders in older test data decode as a new card).
- **Weights:** the library's own default FSRS-6 weights, `FSRSDefaults.defaultWv6` (21 values; public on the pinned main commit), passed as `FSRSParameters(w:)` because the parameters' own default `w` is still FSRS-5. Never a hand-copied weight list. `ReviewSchedulerTests/usesFSRS6Weights` pins the count. `enableShortTerm = false`; `enableFuzz = true` in the app, `false` in tests.
- **Dates:** every date computed by FSRS goes through `.storageRounded` before it is stored (ADR-0012). `reviewCard.dueAt` always equals the stored card's `due`.
- **`reviewLog.rating`** is `ReviewRating.rawValue`: again 1, hard 2, good 3, easy 4 (FSRS raw values). `.manual` is never used.
- **`introducedAt`** is set by the first rating of a card (same transaction as its log), not when a card is shown. A card shown but never rated stays new.
- **Suspension is stored and always recomputed by one rule:** `FrequencyPolicy.suspendedReason(cardType:highlightHasMasteryCards:override:category:)`. A passive card of a highlight with Mastery cards → `mastery`; else effective frequency (card override, else category) Off → `user` when the override is Off, else `frequencyOff`; else not suspended. `ReviewSuspension.recompute` applies it after every change that can affect it: category frequency, a document's category, category delete, card override, Mastery insert/delete, card insert.
- **Cloze cards store their own text:** `answer` holds the display text (`editedText ?? text`) at the time the cloze was made; `clozeRanges` are UTF-16 ranges into that text. Later highlight edits don't break the ranges. Q&A cards use `question` and `answer`.
- **Reschedule from the last review** (frequency change): new due = `lastReview` + FSRS-6 interval for the card's stability at the new retention (`S / F · (r^(1/D) − 1)`, `D = −w[20]`, `F = 0.9^(1/D) − 1`), rounded to whole days, clamped to 1…36,500, no fuzz. New cards and cards never reviewed keep their due date.
- **No schema change in Phase 2** (no `v3`). Review settings live in `UserDefaults` (ADR-0015).

## Alternatives considered
Store `FSRS.Card`'s own Codable output (ties stored data to library internals); hand-copy the FSRS-6 weights (drifts from the library); compute suspension in every query instead of storing it (the schema and the `reviewCard_due` partial index already assume a stored flag); keep cloze ranges against the live highlight text (an edit would shift every range); a `clozeText` column (needs `v3`).

## Consequences
ARCHITECTURE §10 is amended to point here. `.claude/agents/review-engine.md` still names `FSRSDefaults.defaultWv6`; only the user can edit agent files. Reviewers reject `import FSRS` outside `ReviewScheduler.swift` and its tests, and any write to `suspended`/`suspendedReason` that doesn't go through `ReviewSuspension`.
