# T05: GRDB records, part 1: categories, documents, highlights, tags, notes

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T04
- **ADRs:** docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Add the Swift record types for the library and annotation tables, the shared `StudyRecord` protocol (Unix-second dates), and the `TestData` factory used by every later test. Part of epic E0.2.

Read first: ADR-0012, ARCHITECTURE §4 (tables `category` … `documentNote`). Types from T03 (`ModelEnums.swift`, `Anchor.swift`, `ColumnValues.swift`) and `BuiltinCategory` (T04) already exist; read those files.

## Files to touch
- `StudyReader/Core/Models/StudyRecord.swift` (new)
- `StudyReader/Core/Models/DocumentCategory.swift` (new)
- `StudyReader/Core/Models/LibraryDocument.swift` (new; contains `LibraryDocument` and `DocumentText`)
- `StudyReader/Core/Models/Highlight.swift` (new)
- `StudyReader/Core/Models/Tagging.swift` (new; `LibraryTag`, `HighlightTag`, `DocumentTag`)
- `StudyReader/Core/Models/DocumentNote.swift` (new)
- `StudyReaderTests/Support/TestData.swift` (new)
- `StudyReaderTests/CoreTests/RecordRoundTripTests.swift` (new)
- `StudyReaderTests/CoreTests/RecordCodingTests.swift` (new)

## Interfaces to produce

```swift
// StudyRecord.swift
import GRDB
/// Shared conformance for every GRDB record (ADR-0012). Dates are stored as REAL Unix seconds.
protocol StudyRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    // Declared as requirements: GRDB 7.11 calls these through its own protocol requirements,
    // so an extension-only method would be ignored and dates would be stored as strings.
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy
    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy
}
extension StudyRecord {
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy { .timeIntervalSince1970 }
    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy { .timeIntervalSince1970 }
}
```
Check the exact requirement signatures in the resolved GRDB sources (search the checked-out package under DerivedData `SourcePackages/checkouts/GRDB.swift` for `databaseDateEncodingStrategy`). If GRDB 7.11 declares them differently (e.g. as static properties), match GRDB's form and say so in your report. Test AC 1 proves it works.

Every record below: `struct`, conforms to `StudyRecord, Equatable` (plus `Identifiable` when it has `id`), declares `static let databaseTableName = "<table>"`. Property names and order follow the table columns. Defaults mirror SQL defaults so the synthesized memberwise init can omit them.

```swift
struct DocumentCategory: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "category"
    var id: String
    var name: String
    var isBuiltin: Bool = false
    var frequency: ReviewFrequency = .normal
    var autoCreateCards: Bool = true
    var sortOrder: Int = 0
}

struct LibraryDocument: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "document"
    var id: String
    var title: String
    var author: String = ""
    var categoryId: String
    var fileType: FileType
    var fileHash: String
    var originalFilename: String
    var originalBookmark: Data? = nil
    var storedPath: String
    var pageCount: Int? = nil
    var coverPath: String? = nil
    var coverSource: CoverSource = .automatic
    var extractionStatus: ExtractionStatus = .pending
    var extractionVersion: Int = 0
    var pdfPosition: PDFPosition? = nil      // JSON column
    var textPosition: Int? = nil
    var progress: Double = 0
    var addedAt: Date
    var lastOpenedAt: Date? = nil
}

struct DocumentText: StudyRecord, Equatable {
    static let databaseTableName = "documentText"
    var documentId: String
    var unitIndex: Int
    var startOffset: Int
    var text: String
    var runs: [TextRun]? = nil               // JSON column
}

struct Highlight: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "highlight"
    var id: String
    var documentId: String
    var kind: HighlightKind
    var view: ReaderViewKind
    var color: HighlightColor = .yellow
    var text: String = ""
    var richText: String = ""
    var editedText: String? = nil
    var note: String = ""
    var pageIndex: Int? = nil
    var positionKey: Double
    var anchor: Anchor                       // JSON column
    var anchorStatus: AnchorStatus = .ok
    var imagePath: String? = nil
    var createdAt: Date
    var updatedAt: Date
}

struct LibraryTag: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "tag"
    var id: String
    var name: String
    var createdAt: Date
}

struct HighlightTag: StudyRecord, Equatable {
    static let databaseTableName = "highlightTag"
    var highlightId: String
    var tagId: String
}

struct DocumentTag: StudyRecord, Equatable {
    static let databaseTableName = "documentTag"
    var documentId: String
    var tagId: String
}

struct DocumentNote: StudyRecord, Equatable {
    static let databaseTableName = "documentNote"
    var documentId: String
    var body: String = ""
    var updatedAt: Date
}
```
Don't add associations, query helpers, or `persistenceConflictPolicy` (never REPLACE, ADR-0012). Don't use the `UUID` type for ids.

```swift
// StudyReaderTests/Support/TestData.swift
import Foundation
@testable import StudyReader
enum TestData {
    /// Whole-second date so REAL round-trips are exact.
    static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    static func document(
        id: String = UUID().uuidString,
        title: String = "Test Document",
        author: String = "",
        categoryId: String = BuiltinCategory.lectureSlides.id,
        fileType: FileType = .pdf,
        fileHash: String? = nil,              // nil → unique: "hash-" + id
        addedAt: Date = referenceDate
    ) -> LibraryDocument                       // storedPath "<id>/original.pdf" or ".md"; originalFilename "test.pdf"/"test.md"

    static func highlight(
        documentId: String,
        id: String = UUID().uuidString,
        text: String = "Sample highlight text",
        note: String = "",
        color: HighlightColor = .yellow,
        positionKey: Double = 0,
        createdAt: Date = referenceDate
    ) -> Highlight   // kind .text, view .markdown, richText = text, updatedAt = createdAt,
                     // anchor .text(TextAnchor(start: Int(positionKey), length: text.utf16.count, text: text,
                     //                         prefix: "", suffix: "", sourceVersion: 1))

    static func tag(name: String, id: String = UUID().uuidString, createdAt: Date = referenceDate) -> LibraryTag
}
```

## Acceptance criteria
1. A saved `LibraryDocument` stores `addedAt` as REAL `1790000000` (`SELECT typeof(addedAt), addedAt FROM document`), and `id` as TEXT. → test `RecordCodingTests/datesAndIdsStoredAsSchemaTypes`
2. Enums are stored as raw values: `fileType = 'pdf'`, `coverSource = 'default'`, `highlight.color` INTEGER `2` for `.blue`, `highlight.view = 'markdown'`, `category.frequency = 'high'`. → test `RecordCodingTests/enumsStoredAsRawValues`
3. `highlight.anchor` is TEXT whose JSON has `"type"`; `document.pdfPosition` is NULL when nil and JSON with `pageIndex` when set; `documentText.runs` is JSON text. → test `RecordCodingTests/jsonColumnsStoredAsText`
4. Each of the 5 seeded categories fetches as `DocumentCategory` with the `BuiltinCategory` values. → test `RecordRoundTripTests/seededCategoriesDecode`
5. Insert-then-fetch returns an equal value for: a custom `DocumentCategory`, a `LibraryDocument` with every optional set (bookmark data, pdfPosition, lastOpenedAt…), a `DocumentText` with runs, a `Highlight` with a `.pdf` anchor spanning two pages, a `Highlight` with an `.image` anchor, `LibraryTag` + `HighlightTag` + `DocumentTag`, a `DocumentNote`. → tests `RecordRoundTripTests/categoryRoundTrip`, `documentRoundTrip`, `documentTextRoundTrip`, `pdfHighlightRoundTrip`, `imageHighlightRoundTrip`, `taggingRoundTrip`, `documentNoteRoundTrip`
6. Updating a highlight's `note` with `update(db)` keeps one row and the FTS index finds the new note (proves no REPLACE). → test `RecordRoundTripTests/updateKeepsRowAndIndex`
7. `LibraryTag` names are case-insensitively unique at the DB level: inserting "Exam" then "exam" throws. → test `RecordRoundTripTests/tagNameUniqueNoCase`

All tests use `AppDatabase.makeInMemory()` and `TestData`.

## Out of scope
- Review, export, embedding records (T06). Repositories (T07).
- Tag rename/merge logic, `#tag` parsing, highlight services (Phase 1).

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-23, Sonnet (effort medium): APPROVED. Tests 49/49, columns match §4. Date strategies declared as protocol requirements (GRDB 7.11 ignores extension-only); spec text updated.
