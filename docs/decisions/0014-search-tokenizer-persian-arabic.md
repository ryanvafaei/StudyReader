# ADR-0014: Search tokenizer for Persian and Arabic text

- Status: Accepted
- Date: 2026-10-24 (from bug hunt `docs/bugs/phase-0.md` M3)

## Context
SPEC requires Persian content to work. The v1 tokenizer `unicode61 remove_diacritics 2` splits words at ZWNJ (U+200C) and at Arabic harakat (category Mn), and treats Arabic yeh/kaf (ي ك) and Persian yeh/kaf (ی ک) as different letters. So `میخواهم` doesn't find `می‌خواهم`, and `کتاب` finds neither `كتاب` nor `كِتَاب`. PDFs also often contain Arabic presentation forms (U+FB50–U+FEFF) and Latin ligatures (ﬁ). The fix must run on-device with SQLite FTS5 and GRDB, and must not change stored text, because anchors use UTF-16 offsets.

## Decision
- A GRDB `FTS5WrapperTokenizer`, Swift type `SearchTokenizer`, SQL name **`studyreader`**, wraps `unicode61 remove_diacritics 2 tokenchars <joiners>`. The joiners are U+200C ZWNJ, U+00AD soft hyphen, U+0640 tatweel, U+064B–U+065F and U+0670. unicode61 then keeps these inside a token, and still lowercases and removes Latin diacritics.
- Each token goes through `SearchTokenNormalizer.normalize`:
  1. NFKC.
  2. Remove the joiner scalars and whitespace.
  3. Fold ي U+064A and ى U+0649 to ی U+06CC, ك U+0643 to ک U+06A9, and ۀ U+06C0 to ه U+0647.
  4. Lowercase.
  An empty result emits no token.
- FTS5 tokenizes MATCH strings with the table's tokenizer, so queries are normalized the same way. `SearchQueryParser` doesn't normalize. `snippet()` reports the original text, because offsets come from the wrapped tokenizer.
- The tokenizer is registered in `AppDatabase.makeConfiguration()` with `prepareDatabase`, so every connection has it: writer, pool readers and tests. Migration `v2` (ADR-0013) recreates and rebuilds the four FTS tables with it.
- Normalization is part of the index format. Any change to `SearchTokenNormalizer` or to the joiner list needs a new migration that runs `'rebuild'` on all four FTS tables. `SearchTokenizerTests` pins the outputs.

## Alternatives considered
- Normalize the text in a SQL function called by the triggers: `snippet()`, `'rebuild'` and `'integrity-check'` read the un-normalized content table, so the index and the content would disagree.
- Store normalized text: this breaks UTF-16 anchors and changes what the user sees.
- A contentless FTS table holding normalized text: no `snippet()`, so Phase 1 would have to build snippets in Swift.
- `tokenchars` without a wrapper: words stop splitting, but ZWNJ and the yeh/kaf forms still don't match.
- The `trigram` tokenizer: bigger index, no folding, substring semantics, and a 3-character minimum.

## Consequences
- Tools without the tokenizer, such as the `sqlite3` CLI, fail with "no such tokenizer: studyreader" when they query FTS tables or write to indexed tables. Reading ordinary tables still works. This is acceptable for a single-user app.
- Not folded: alef forms (أ إ آ → ا), teh marbuta, Persian and Arabic-Indic digits. Adding any of them later needs a new migration.
- There is a small Swift string cost per token. That's fine at course-material sizes.
