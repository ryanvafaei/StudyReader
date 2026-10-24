# T30: Rename the ADR-0014 file to an English-only name

- **Phase:** 1 (docs only)
- **Agent:** orchestrator (main session). It needs `git mv`, which isn't in the `.claude/settings.json` allow list, so the user approves one permission prompt. The architect has no Bash and can't do it. Fallback if the orchestrator prefers to delegate: `data-layer` (has Bash), given this spec.
- **Depends on:** none
- **ADRs:** docs/decisions/0014-* (the file being renamed)
- **Visual check needed:** no

## Goal
ADR-0014's decision is English-only (user decisions 2026-10-24, T28), but its file name still says Persian/Arabic, and line 5 of the ADR explains that only for link stability. Rename the file and fix every reference so the name matches the decision.

## Steps
1. Rename with history kept (one command, from the repo root):
   `git mv docs/decisions/0014-search-tokenizer-persian-arabic.md docs/decisions/0014-search-tokenizer-english.md`
2. In the renamed ADR, replace line 5 (`- The file name still says "persian-arabic" for link stability; the decision is English-only.`) with:
   `- File renamed 2026-10-24 (T30) to match the English-only decision.`
3. Update every reference. At planning time these were the only ones outside this spec (Grep the repo for `0014-search-tokenizer-persian-arabic`, excluding `.references/`, to confirm):
   - `docs/tasks/phase-0/README.md` line 30: link target → `../../decisions/0014-search-tokenizer-english.md`.
   - `docs/tasks/phase-0/T18-search-tokenizer.md` line 7: path → `docs/decisions/0014-search-tokenizer-english.md`; change the parenthesis to `(read it in full; English-only)`.
   - `docs/tasks/phase-0/T19-migration-v2.md` line 6: path → `docs/decisions/0014-search-tokenizer-english.md`; change the parenthesis to `(English-only)`.
   - The architect's memory file `.claude/agent-memory/architect/project_conventions.md` was already updated during planning; leave it.
4. Don't edit review logs, bug reports or anything under `.references/`.

## Acceptance criteria
1. `docs/decisions/0014-search-tokenizer-english.md` exists and `git status` shows it as a rename (R), not a delete plus add. → check: `git status`
2. Grep for `0014-search-tokenizer-persian-arabic` (whole repo, excluding `.references/`) matches only this spec file. → check: Grep
3. Grep for `persian-arabic` (case-insensitive, same scope) matches only this spec file. → check: Grep
4. Every Markdown link to ADR-0014 resolves (the three files above point at the new name). → check: read the three lines
5. No code or build files change, so `./scripts/test.sh` isn't needed. The code-reviewer checks items 1–4.

Commit message: `T30: Rename ADR-0014 file to an English-only name`.

## Out of scope
- Changing the ADR's decision text (beyond line 5) or ADR-0014's number.
- Renaming any other ADR.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. Rename shown as R, no old-name references remain, three links resolve.
