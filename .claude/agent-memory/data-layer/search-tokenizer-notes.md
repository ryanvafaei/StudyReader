---
name: search-tokenizer-notes
description: T18 studyreader FTS5 tokenizer files, registration point, and test approach
metadata:
  type: reference
---

- `Core/Database/SearchTokenizer.swift`: `SearchTokenNormalizer` (NFKC, drop U+00AD, lowercase) + `SearchTokenizer: FTS5WrapperTokenizer` (unicode61 remove_diacritics 2, tokenchars U+00AD). Compiles under Swift 6 strict concurrency with no Sendable workarounds.
- Registered in `AppDatabase.makeConfiguration()` via `configuration.prepareDatabase { $0.add(tokenizer: SearchTokenizer.self) }`; covers pool readers and in-memory queues.
- Tests: `CoreTests/SearchTokenizerTests` (scratch `sample_fts` table with `tokenize='studyreader'`; uses `SearchSamples`). NFD resume matches fine with unicode61 remove_diacritics 2.
- Changing the normalizer or joiner list changes the index format: needs a new migration rebuilding all FTS tables (ADR-0014). Real FTS tables switch in T19.
