# ADR-0010: Mastery suggestions via on-device Foundation Models (optional)

- Status: Accepted
- Date: 2026-10-23

## Context
Writing cloze and Q&A cards by hand is slow; paid AI APIs are out of scope.

## Decision
Offer "Suggest with Apple Intelligence" only when `SystemLanguageModel.default.availability == .available`. Use guided generation (`@Generable`) to draft one cloze and one Q&A; user confirms before anything is saved.

## Alternatives considered
Cloud LLM APIs (excluded); no AI assistance.

## Consequences
Feature silently absent on Macs without Apple Intelligence; everything else unaffected.
