# ADR-0001: Build from scratch on libraries, not a fork

- Status: Accepted
- Date: 2026-10-23

## Context
Several open-source macOS readers exist (reader-source, annotate, YoPDF, PDFReader). The closest, reader-source, bundles EPUB, AI chat, a Supabase backend, accounts, and a browser (~25k lines). EPUB is banned for this project, and none has FTS5 search, spaced repetition, or Google export.

## Decision
Write our own app on GRDB, swift-markdown, swift-fsrs, and GoogleSignIn. Keep MIT/Apache repos in `.references/` as read-only references for specific files (DEPENDENCIES.md §3).

## Alternatives considered
Fork reader-source and strip it; fork YoPDF (too early, writes annotations into PDFs); use PDFReader (GPL-3.0).

## Consequences
More code to write, but every line fits our architecture and scope. Copied snippets keep their license notice and go into THIRD_PARTY_NOTICES.md.
