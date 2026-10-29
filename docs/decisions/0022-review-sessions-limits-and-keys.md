# ADR-0022: Review sessions, daily limits and review keys

- Status: Accepted (2026-10-29; the user answered Q1–Q9 as recommended)
- Date: 2026-10-29
- Amended 2026-10-29 (T122a): the themed completion rule changed from "only ratings" to "any reason the queue runs out". The user decided it, so that a themed review whose cards were all deleted or suspended is not left due forever. Leaving early still never completes.

## Context
SPEC F-15 and F-20 describe what goes into a session, but not how the daily limit counts across several sessions on one day, what "persists across restart" means for a session in progress, or how the plain keys Space and 1–4 can coexist with the note and edit fields on the same screen. ARCHITECTURE §10.2 defines the builders.

## Decision
- **Review day.** A review day starts at 04:00 local time (`ReviewDay.start(containing:calendar:)`). "Today", "rated today", weekday and N-day intervals all use review days.
- **Daily budget per review day (*Q1).** Due cards: `dailyLimit` minus the cards already rated today in daily sessions that were not introduced today. New cards: `newPerDay` minus the cards introduced today in any session (*Q5). Cards rated today in any session are never offered again the same day.
- **A session is built once, when it starts,** and held in memory by `ReviewSessionModel`. It is not stored. Every rating is written at once (card and log in one transaction), so quitting mid-session loses nothing; after a restart the next session is built again from the database.
- **Skip** moves the current card to the end of the in-memory queue, writes nothing and is not counted.
- **A themed session is completed** when its queue runs out for any reason: rated, deleted or suspended (a drop, a frequency change to Off or a card that is gone when the session reads it); then `lastCompletedAt = now`, once per session. Leaving early (`endSession()` with cards still queued) doesn't complete it. A themed review whose selection is empty shows "No cards match this review" and counts as completed (*Q6).
- **Card display.** Passive cards show everything at once (text or image, title, page, colour label, note, tags) and can be rated at once. Cloze and Q&A cards hide the answer, the note and the tags until Space or "Show Answer".
- **Review keys** (Space, 1–2 or 1–4) are handled only by the focused review card (`.focusable()` + `.onKeyPress`), never by `.keyboardShortcut` without modifiers: such shortcuts fire while the user types in the note or edit field. When a text field has focus, every key goes to the field.
- **Flashcards view (*Q3)** offers every F-18 action except rating and Skip (they belong to a session).
- **Reminder (*Q7):** a local notification through `UserNotifications` (Apple framework, no package) at the chosen time, repeating daily, fixed text. Off by default.

## Alternatives considered
A limit per session (a second session the same day would show 15 more due cards); storing the in-progress session (needs `v3` and resume logic for little gain); `.keyboardShortcut("1", modifiers: [])` on the rating buttons (steals digits typed into the note field).

## Consequences
The builders get the day's activity (`ReviewDayActivity`) from the repository and stay pure. Every task that adds a text field to the review screens names the UI test that proves keys typed into it don't rate.
