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
- T12 (upsert guard, ADR-0012 amended): `CoreTests/UpsertConventionTests.swift` (6 tests). Only allowed upsert shape: `try record.upsertAndFetch(db, onConflict: ["id"])`. `save` is non-mutating in GRDB 7.11 (a `var` gives a warning). `scripts/test.sh` filters need struct names (`StudyReaderTests/UpsertConventionTests`), not `@Suite` display names; the display-name filter runs 0 tests and still reports success.
- Full suite after T12: 93 tests in 21 suites.
- T34 (Phase 1): `DocumentRepository` gained delete(id:fileStore:), updateMetadata, column-limited position/cover/extraction updates, observeItems (`LibraryItem` in `Core/Models/LibraryItem.swift`, which also holds `RepositoryError.notFound`). `CategoryRepository` gained create/rename/delete (delete moves documents to Other in the same write) and observeUsage (`CategoryUsage`). Errors: `CategoryError`, `DocumentEditError`.
- T34 pitfalls: `FileStore` accepts only canonical uppercase UUID strings (`UUID(uuidString:)?.uuidString == id`), so use `UUID().uuidString` for document ids that touch folders. Category rename to the same name in different case is allowed (the row is excluded from the duplicate check). For observations, put multi-row inserts in one `write` so the first `next()` after the change sees all rows; separate writes can emit intermediate values. The argument order of `TestData.document` is id, title, author, categoryId, fileType, fileHash, addedAt, so `categoryId:` must come before `fileHash:`.
- T34 test count: DocumentRepositoryTests 15 tests, CategoryRepositoryTests 7 tests (both suites pass).
