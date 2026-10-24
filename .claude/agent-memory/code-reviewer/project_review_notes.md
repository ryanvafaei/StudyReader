---
name: review-notes-fts-tokenizer
description: Facts useful when reviewing FTS/tokenizer/database tasks in StudyReader (GRDB wrapper tokenizer behaviour, git status noise)
metadata:
  type: project
---

GRDB `FTS5WrapperTokenizer` forwards the wrapped tokenizer's iStart/iEnd byte offsets and lets `accept` pass flags unchanged, so snippet()/highlight offsets stay correct if `accept` only rewrites the token text. Verify against `build/SourcePackages/checkouts/GRDB.swift/GRDB/FTS/FTS5WrapperTokenizer.swift` rather than re-deriving.

**Why:** T18 (SearchTokenizer, ADR-0014) review relied on this; avoids re-reading the source each time.

**How to apply:** For tokenizer changes, check that accept() does not emit multiple tokens (needs colocated flag) or alter flags; check changes bump the index format (new migration rebuilding FTS tables, per ADR-0014).

Git status at session start routinely shows unrelated modified `.claude/`, `CLAUDE.md`, and untracked `scripts/` files; ignore them, review only the task's files.

T19 (migration v2) review facts: SchemaV2.sql must match the spec SQL verbatim; check golden `Fixtures/schema/v2.sql` has 12 non-`__` triggers, 4 studyreader virtual tables, 4 new indexes, and that `git status` shows SchemaV1.swift / v1.sql unmodified. FTS prefix queries must be `"\"" + term + "\"*"` (star outside quotes); quoting the star makes it a literal. Implementer tests use `valueN` variable names around `#expect` deliberately.
