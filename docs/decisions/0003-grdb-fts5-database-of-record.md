# ADR-0003: GRDB + SQLite FTS5; annotations live in the database

- Status: Accepted
- Date: 2026-10-23

## Context
We need relational data (documents, highlights, tags, cards), live UI updates, migrations, and fast full-text search across pages, highlights, and notes.

## Decision
SQLite via GRDB `DatabasePool` (WAL), append-only migrations, FTS5 external-content tables synchronized with triggers. Highlights are never written into the user's PDF files; PDF annotations are display-only.

## Alternatives considered
SwiftData (weaker FTS and migration control); writing standard PDF annotations into files (YoPDF's approach; risks modifying originals, harder search).

## Consequences
One source of truth; originals untouched. Annotated-PDF export would be a separate future feature.
