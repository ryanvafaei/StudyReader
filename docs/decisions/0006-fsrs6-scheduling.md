# ADR-0006: Spaced repetition with FSRS-6 via swift-fsrs

- Status: Accepted
- Date: 2026-10-23

## Context
Review needs a modern scheduler with per-content-type frequency.

## Decision
Use `open-spaced-repetition/swift-fsrs` (MIT, FSRS-6 weights `defaultWv6`), long-term scheduler (`enableShortTerm = false`), fuzz on (off in tests). Frequency maps to desired retention: low 0.80, normal 0.90, high 0.95; off suspends. Card override beats category.

## Alternatives considered
SM-2 (older, less accurate); 4rays/swift-fsrs (unmaintained since 2024); own FSRS implementation.

## Consequences
Scheduling logic is a thin, fully unit-tested wrapper around the library.
