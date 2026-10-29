# ADR-0006: Spaced repetition with FSRS-6 via swift-fsrs

- Status: Accepted
- Date: 2026-10-23

## Context
Review needs a modern scheduler with per-content-type frequency.

## Decision
Use `open-spaced-repetition/swift-fsrs` (MIT, FSRS-6 weights `defaultWv6`), long-term scheduler (`enableShortTerm = false`), fuzz on (off in tests). Frequency maps to desired retention: low 0.80, normal 0.90, high 0.95; off suspends. Card override beats category.

## Amendment 2026-10-29 (user decision): pin swift-fsrs main
The tagged release swift-fsrs 5.0.0 is FSRS-5 (19 weights, fixed decay) with an internal API; FSRS-6 is public only on unreleased `main`. The package is therefore pinned by revision: **swift-fsrs main @ `4fbaf20184d62f82a9f44f343337c61a2c5483e9` (2026-05-25, 41 commits after 5.0.0, MIT) until a release ships FSRS-6**. At that commit `FSRSDefaults.defaultWv6` (21 weights), `FSRSParameters(requestRetention:w:enableFuzz:enableShortTerm:)`, `FSRS(parameters:)` and `next(card:now:grade:)` are public. `project.yml` uses `revision:`; `Package.resolved` (committed, ADR-0011) records the same revision. Backlog: move to the first tagged release that includes FSRS-6 (`docs/BACKLOG.md`). The fallback if the pin ever stops building is an own FSRS-6 implementation in `ReviewScheduler.swift` with the 21 published weights.

## Alternatives considered
SM-2 (older, less accurate); 4rays/swift-fsrs (unmaintained since 2024); own FSRS implementation.

## Consequences
Scheduling logic is a thin, fully unit-tested wrapper around the library.
