# T07: Repository skeleton: CategoryRepository, DocumentRepository

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T05
- **ADRs:** docs/decisions/0003-grdb-fts5-database-of-record.md, docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Establish the repository pattern every later repository copies: a `Sendable` struct over `AppDatabase`, `async` reads/writes, and an `AsyncValueObservation` for live UI lists. Only two repositories, with only the methods listed. Part of epic E0.2. Phase 1 extends `DocumentRepository` (delete with file cleanup, metadata updates) and adds the rest.

Read first: ARCHITECTURE §3 (repository and ValueObservation bullets). Read `AppDatabase.swift`, `DocumentCategory.swift`, `LibraryDocument.swift`, `TestData.swift`.

## Files to touch
- `StudyReader/Core/Repositories/CategoryRepository.swift` (new)
- `StudyReader/Core/Repositories/DocumentRepository.swift` (new)
- `StudyReaderTests/CoreTests/CategoryRepositoryTests.swift` (new)
- `StudyReaderTests/CoreTests/DocumentRepositoryTests.swift` (new)

## Interfaces to produce

```swift
import GRDB

/// Pattern for all repositories: the only code that touches GRDB (besides AppDatabase/migrations).
struct CategoryRepository: Sendable {
    private let writer: any DatabaseWriter
    init(database: AppDatabase)                     // writer = database.writer

    /// ORDER BY sortOrder ASC, name ASC
    func fetchAll() async throws -> [DocumentCategory]
    func fetch(id: String) async throws -> DocumentCategory?
    /// Live list with the same ordering; first element is the current value.
    func observeAll() -> AsyncValueObservation<[DocumentCategory]>
}

struct DocumentRepository: Sendable {
    private let writer: any DatabaseWriter
    init(database: AppDatabase)

    /// Throws GRDB's DatabaseError on constraint violations (e.g. duplicate fileHash).
    func insert(_ document: LibraryDocument) async throws
    func fetch(id: String) async throws -> LibraryDocument?
    /// ORDER BY addedAt DESC, title ASC (SPEC F-01 default sort: newest first)
    func fetchAll() async throws -> [LibraryDocument]
    /// Live list, same ordering.
    func observeAll() -> AsyncValueObservation<[LibraryDocument]>
}
```
Implementation pattern (copy for both):
```swift
func fetchAll() async throws -> [DocumentCategory] {
    try await writer.read { db in
        try DocumentCategory
            .order(Column("sortOrder").asc, Column("name").asc)
            .fetchAll(db)
    }
}

func observeAll() -> AsyncValueObservation<[DocumentCategory]> {
    ValueObservation
        .tracking { db in
            try DocumentCategory.order(Column("sortOrder").asc, Column("name").asc).fetchAll(db)
        }
        .values(in: writer)
}

func insert(_ document: LibraryDocument) async throws {
    try await writer.write { db in try document.insert(db) }
}
```
Use `Column("…")` with the exact column names. No raw SQL needed. If GRDB 7.11 spells an API differently (e.g. `values(in:)` arguments), follow GRDB and mention it in your report. Don't add delete/update methods; Phase 1 adds them with their tests.

## Acceptance criteria
1. `CategoryRepository.fetchAll()` returns the 5 built-ins in order Lecture slides, Paper, Book chapter, Notes, Other. → test `CategoryRepositoryTests/fetchAllReturnsBuiltinsInOrder`
2. `fetch(id: BuiltinCategory.other.id)` returns "Other"; an unknown id returns nil. → test `CategoryRepositoryTests/fetchById`
3. `observeAll()` first emits the 5 built-ins; after inserting a custom category with `sortOrder 10` (through `database.writer` in the test), the next emission has 6 with the custom one last. → test `CategoryRepositoryTests/observeAllEmitsChanges`
4. `DocumentRepository.insert` then `fetch(id:)` returns an equal document; unknown id returns nil. → test `DocumentRepositoryTests/insertAndFetch`
5. `fetchAll()` orders by `addedAt` descending (three documents with different whole-second dates). → test `DocumentRepositoryTests/fetchAllNewestFirst`
6. Inserting a second document with the same `fileHash` throws `DatabaseError`. → test `DocumentRepositoryTests/duplicateHashThrows`
7. `observeAll()` first emits `[]`, then emits 1 document after `insert`. → test `DocumentRepositoryTests/observeAllEmitsAfterInsert`

Observation tests: get `var iterator = repo.observeAll().makeAsyncIterator()`, `await` the first value before writing, then `await` the next. Give these tests `.timeLimit(.minutes(1))`.

## Out of scope
- Delete (with `FileStore` cleanup), metadata update, sort/filter options, other repositories (Phase 1).
- Any UI model.

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-23, Sonnet (effort medium): APPROVED. Tests 63/63, repository pattern sound (Sendable struct, AsyncValueObservation, ordering, observe tests assert post-change emission). Minor: no same-addedAt tie-break test.
