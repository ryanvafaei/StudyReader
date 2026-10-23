---
name: repository-pattern-notes
description: Repository pattern as implemented in T07 (CategoryRepository, DocumentRepository), GRDB 7.11 ValueObservation API spelling, and test patterns for observations and throws
metadata:
  type: reference
---

- Files: `StudyReader/Core/Repositories/CategoryRepository.swift`, `DocumentRepository.swift`. Tests: `StudyReaderTests/CoreTests/CategoryRepositoryTests.swift`, `DocumentRepositoryTests.swift` (7 tests). Full suite after T07: 63 tests in 14 suites.
- Pattern: `struct X: Sendable { private let writer: any DatabaseWriter; init(database: AppDatabase) { writer = database.writer } }`. Reads use `writer.read { }`, writes `writer.write { }`.
- GRDB 7.11 spelling: `ValueObservation.tracking { db in ... }.values(in: writer)` returns `AsyncValueObservation<Value>`. No changes needed from the spec.
- Observation tests: `var iterator = repo.observeAll().makeAsyncIterator()`, then `try await iterator.next()` for each emission. Use `@Test(.timeLimit(.minutes(1)))`.
- Throwing async call: `await #expect(throws: DatabaseError.self) { try await repo.insert(dup) }` compiles and passes.
- `Column("addedAt").desc` and `fetchOne(db, key: id)` work for `LibraryDocument` and `DocumentCategory`.
- Phase 1 extends `DocumentRepository` (delete with FileStore cleanup, metadata update). Don't add delete/update before then.
