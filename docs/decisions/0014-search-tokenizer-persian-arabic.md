# ADR-0014: Search tokenizer `studyreader` (English text: ligatures, soft hyphens, case, diacritics)

- Status: Accepted
- Date: 2026-10-24 (from bug hunt `docs/bugs/phase-0.md` M3). Amended 2026-10-24: scope narrowed to English-only by the user.
- The file name still says "persian-arabic" for link stability; the decision is English-only.

## Context
The v1 tokenizer `unicode61 remove_diacritics 2` lowercases and removes Latin diacritics, but text extracted from PDFs often contains Latin ligatures (ﬁ U+FB01, ﬂ U+FB02) and soft hyphens (U+00AD) at hyphenation points. unicode61 keeps `ﬁnd` as a token that never matches `find`, and splits `photo\u{00AD}synthesis` into `photo` and `synthesis`. The fix must run on-device with SQLite FTS5 and GRDB, and must not change stored text, because anchors use UTF-16 offsets. App content is English-only for now (user decision 2026-10-24).

## Decision
- A GRDB `FTS5WrapperTokenizer`, Swift type `SearchTokenizer`, SQL name **`studyreader`**, wraps `unicode61 remove_diacritics 2 tokenchars <joiners>`. The only joiner is U+00AD soft hyphen. unicode61 then keeps it inside a token, and still lowercases and removes Latin diacritics (precomposed and combining U+0300 marks).
- Each token goes through `SearchTokenNormalizer.normalize`:
  1. NFKC (unfolds ligatures: ﬁ → fi, ﬂ → fl).
  2. Remove the joiner scalars (U+00AD).
  3. Lowercase.
  An empty result emits no token.
- FTS5 tokenizes MATCH strings with the table's tokenizer, so queries are normalized the same way. `SearchQueryParser` doesn't normalize. `snippet()` reports the original text, because offsets come from the wrapped tokenizer.
- The tokenizer is registered in `AppDatabase.makeConfiguration()` with `prepareDatabase`, so every connection has it: writer, pool readers and tests. Migration `v2` (ADR-0013) recreates and rebuilds the four FTS tables with it.
- Normalization is part of the index format. Any change to `SearchTokenNormalizer` or to the joiner list needs a new migration that runs `'rebuild'` on all four FTS tables. `SearchTokenizerTests` pins the outputs.

## Alternatives considered
- Normalize the text in a SQL function called by the triggers: `snippet()`, `'rebuild'` and `'integrity-check'` read the un-normalized content table, so the index and the content would disagree.
- Store normalized text: this breaks UTF-16 anchors and changes what the user sees.
- A contentless FTS table holding normalized text: no `snippet()`, so Phase 1 would have to build snippets in Swift.
- `tokenchars` without a wrapper: soft-hyphenated words stop splitting but still don't match the typed word, and ligatures still don't fold.
- The `trigram` tokenizer: bigger index, no folding, substring semantics, and a 3-character minimum.
- Persian/Arabic folding (ZWNJ, Arabic marks, tatweel, Arabic yeh/kaf → Persian letters): planned first, then **deliberately dropped** by the user because app content is English-only for now. It can be added later as a new tokenizer version: change `SearchTokenNormalizer` and the joiner list, and ship a new migration that rebuilds all four FTS tables.

## Consequences
- Tools without the tokenizer, such as the `sqlite3` CLI, fail with "no such tokenizer: studyreader" when they query FTS tables or write to indexed tables. Reading ordinary tables still works. This is acceptable for a single-user app.
- Non-Latin text is indexed by plain unicode61 rules. Persian words split at ZWNJ, and Arabic and Persian letter forms don't match each other. Rendering and highlighting of such text are unaffected.
- There is a small Swift string cost per token. That's fine at course-material sizes.
