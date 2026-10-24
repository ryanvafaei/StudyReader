# T36: TagRepository

- **Phase:** 1 (E1.5: F-10)
- **Agent:** data-layer
- **Depends on:** T34
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (dedupe by lookup, never upsert)
- **Visual check needed:** no

## Goal
Tags on highlights and documents (SPEC F-10): case-insensitively unique names stored as typed, find-or-create, rename, merge, delete, per-item tag sets, bulk add/remove for the browser, and live usage counts for the tag manager.

## Files to touch
- `StudyReader/Core/Repositories/TagRepository.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: add `let tagRepository: TagRepository`)
- `StudyReaderTests/CoreTests/TagRepositoryTests.swift` (new)

## Interfaces to produce
```swift
enum TagError: Error, Equatable, LocalizedError {
    case invalidName          // "Tag names need 1 to 40 characters."
    case duplicateName        // "A tag with this name already exists."
    case notFound             // "This tag no longer exists."
}

struct TagUsage: Sendable, Equatable, Identifiable {
    var tag: LibraryTag
    var highlightCount: Int
    var documentCount: Int
    var id: String { tag.id }
}

struct TagRepository: Sendable {
    init(database: AppDatabase)

    /// Trims whitespace, removes one leading "#", trims again. Valid: 1–40 Characters. Otherwise nil.
    static func normalizedName(_ raw: String) -> String?

    /// Lookup by name (the column is COLLATE NOCASE, so `Column("name") == name` is case-insensitive),
    /// else insert LibraryTag(id: UUID().uuidString, name: <normalized, as typed>, createdAt: date).
    /// Throws .invalidName.
    func findOrCreate(name: String, at date: Date) async throws -> LibraryTag
    func fetchAll() async throws -> [LibraryTag]                       // ORDER BY name COLLATE NOCASE, id
    func observeAll() -> AsyncValueObservation<[LibraryTag]>
    func observeUsage() -> AsyncValueObservation<[TagUsage]>           // same order, counts include 0

    /// Another tag with the same name (case-insensitive) → .duplicateName. Same tag, different case → allowed.
    func rename(id: String, to name: String) async throws
    /// One transaction: for every highlightTag/documentTag of source, add the same link to target unless it
    /// already exists (lookup, then insert), then delete source (its links cascade). source == target → no-op.
    func merge(sourceId: String, into targetId: String) async throws
    func delete(id: String) async throws                                // links cascade; items stay

    func tags(forHighlight highlightId: String) async throws -> [LibraryTag]   // name order
    func observeTags(forHighlight highlightId: String) -> AsyncValueObservation<[LibraryTag]>
    /// Replaces the highlight's set with exactly tagIds (one transaction).
    func setTags(_ tagIds: [String], forHighlight highlightId: String) async throws
    func addTag(_ tagId: String, toHighlights highlightIds: [String]) async throws     // skips existing links
    func removeTag(_ tagId: String, fromHighlights highlightIds: [String]) async throws

    func tags(forDocument documentId: String) async throws -> [LibraryTag]
    func observeTags(forDocument documentId: String) -> AsyncValueObservation<[LibraryTag]>
    func setTags(_ tagIds: [String], forDocument documentId: String) async throws
}
```
- Never `upsert`, never `INSERT OR IGNORE`/REPLACE: check for an existing link with `fetchOne(db, key: ["highlightId": …, "tagId": …])` then `insert`.
- `observeUsage` counts with two grouped queries (`SELECT tagId, COUNT(*) FROM highlightTag GROUP BY tagId`, same for `documentTag`) in the tracking closure.
- Tag edits don't touch FTS tables (tags aren't indexed), but tests that also write highlights still end with `FTSIntegrity.check`.

## Tests (`TagRepositoryTests`, in-memory)
- `normalizedNameRules`: `"  #Exam "` → `"Exam"`; `"#"` → nil; `""` → nil; 40 × "a" valid; 41 × "a" nil; `"##x"` → `"#x"`.
- `uniqueness` (SPEC F-10 AC1): `findOrCreate("Exam")` then `findOrCreate("exam")` and `findOrCreate("  #EXAM ")` return the same id; name stays "Exam"; one row in `tag`. `findOrCreate("")` throws `.invalidName`.
- `renameMerge` (SPEC F-10 AC1): tags "ML" and "Machine Learning"; h1 tagged both, h2 tagged "ML", document d1 tagged "ML". `rename(ml, to: "machine learning")` throws `.duplicateName`; `rename(ml, to: "ml")` works. `merge(sourceId: ml, into: machineLearning)`: h1 has one link (no duplicate), h2 and d1 now have "Machine Learning", the "ML" row is gone. `FTSIntegrity.check` passes.
- `deleteKeepsItems`: delete a tag used by a highlight and a document; both items still exist, links gone.
- `setAndBulkTags`: `setTags([a, b], forHighlight: h)` then `setTags([b], …)` → only b; `addTag(c, toHighlights: [h1, h2])` twice → one link each; `removeTag(c, fromHighlights: [h1])` → only h2 keeps c. Same `setTags` behaviour for a document.
- `observeUsageCounts` (`.timeLimit(.minutes(1))`): first value lists existing tags with counts; adding a link emits updated counts.

## Acceptance criteria
1. Tag names are case-insensitively unique and stored as typed. → tests `TagRepositoryTests/uniqueness`, `normalizedNameRules`
2. Rename and merge update every use. → test `TagRepositoryTests/renameMerge`
3. Delete removes the tag from items and keeps items. → test `TagRepositoryTests/deleteKeepsItems`
4. Per-item sets and bulk add/remove work. → test `TagRepositoryTests/setAndBulkTags`
5. Usage counts are live. → test `TagRepositoryTests/observeUsageCounts`

## Out of scope
- `#tag` parsing in notes (T37), tag UI (T49).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
