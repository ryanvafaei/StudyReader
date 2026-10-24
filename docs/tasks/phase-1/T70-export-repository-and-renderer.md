# T70: ExportRepository, ExportRenderer and Drive folder links

- **Phase:** 1 (E1.8: F-21 rendering and targets)
- **Agent:** integrations
- **Depends on:** T36, T37, T58
- **ADRs:** docs/decisions/0007-google-export-drive-conversion.md, docs/decisions/0018-google-export-seams-and-status.md, ARCHITECTURE §9.1 (the rules below are the exact contract; where ARCHITECTURE §9.1 is less specific, this spec wins)
- **Visual check needed:** no

## Goal
Everything on the data side of export, without network: load the highlights, notes and metadata for an export scope; render them to the exact Markdown format (golden-file tested); store export targets and their status; parse a pasted Google Drive folder link.

## Files to touch
- `StudyReader/Features/Export/ExportContent.swift` (new: value types)
- `StudyReader/Core/Repositories/ExportRepository.swift` (new: scope loading + `exportTarget` CRUD)
- `StudyReader/Features/Export/ExportRenderer.swift` (new)
- `StudyReader/Features/Export/DriveFolderLink.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `let exportRepository: ExportRepository`)
- `StudyReaderTests/ExportTests/ExportRendererTests.swift`, `ExportRepositoryTests.swift`, `DriveFolderLinkTests.swift` (new)
- `StudyReaderTests/Fixtures/golden/export/by-document-all-options.md`, `by-tag-all-options.md`, `by-document-minimal.md`, `empty.md` (new; content exactly as below)

## Interfaces to produce
```swift
enum ExportStatus: String, Sendable, CaseIterable { case never, ok, queued, failed, docMissing, signInRequired }   // ADR-0018

struct ExportHighlight: Sendable, Equatable {
    var id: String
    var documentId: String
    var kind: HighlightKind
    var color: HighlightColor
    var pageIndex: Int?
    /// editedText → RichTextMarkdown.escape(editedText); else richText if non-empty; else escape(text). "" for images.
    var body: String
    var note: String               // trimmed
    var tagNames: [String]         // sorted case-insensitively
    var positionKey: Double
}
struct ExportDocument: Sendable, Equatable {
    var id: String
    var title: String
    var author: String
    var categoryName: String
    var documentNote: String?      // trimmed; nil when empty
    var highlights: [ExportHighlight]   // positionKey, then id
}
struct ExportContent: Sendable, Equatable {
    var scopeName: String
    var documents: [ExportDocument]     // title localizedStandardCompare, then id
}

struct ExportRepository: Sendable {
    init(database: AppDatabase)
    /// document → its title; tag → "#" + name; category → its name; themedReview → its name; all → "All highlights".
    func scopeName(for scope: ExportScope) async throws -> String
    func content(for scope: ExportScope) async throws -> ExportContent
    func content(forHighlightIds ids: [String], scopeName: String) async throws -> ExportContent
    func observeChangeToken() -> AsyncValueObservation<Int>   // emits when highlight, highlightTag, tag, document,
                                                              // documentTag, documentNote or category change (T74)
    // Targets
    func fetchTargets() async throws -> [ExportTarget]         // createdAt asc
    func observeTargets() -> AsyncValueObservation<[ExportTarget]>
    func fetchTarget(id: String) async throws -> ExportTarget?
    func target(for scope: ExportScope) async throws -> ExportTarget?   // first target with an equal scope
    func insertTarget(_ target: ExportTarget) async throws
    func updateOptions(id: String, options: ExportOptions, title: String) async throws
    func setKeepInSync(id: String, _ on: Bool) async throws
    /// Column-limited: lastStatus, lastError, and when non-nil googleFileId, googleFolderId, format, lastExportedAt.
    func recordResult(id: String, status: ExportStatus, error: String?, fileId: String?, folderId: String?,
                      format: ExportFormat?, exportedAt: Date?) async throws
    func clearFileId(id: String) async throws                  // "Create new Doc"
    func removeTarget(id: String) async throws                 // never touches Google
}

enum ExportRenderer {
    /// Pure. Exact format below. Lines joined with "\n"; output ends with exactly one "\n"; no line has trailing
    /// spaces; never two blank lines in a row.
    static func render(_ content: ExportContent, options: ExportOptions, colorLabels: [String],
                       generatedAt: Date, timeZone: TimeZone) -> String
}

enum DriveFolderLink {
    /// Folder ID from: https://drive.google.com/drive/folders/<ID>, …/drive/u/<n>/folders/<ID>, with or without a
    /// query string; https://drive.google.com/open?id=<ID>; or a bare ID (^[A-Za-z0-9_-]{10,}$). Trimmed. Else nil.
    static func folderId(from input: String) -> String?
}
```

## Scope rules (`content(for:)`)
- document: that document's highlights; its note.
- tag: highlights that have the tag (`highlightTag`); documents that contribute at least one; their notes.
- category: highlights of documents in the category; every document in the category with a highlight or a note.
- themedReview: highlights matching its `ThemedReviewFilter` (tags any/all on highlights; documentIds; categoryIds; colors; empty lists = no constraint); documents contributing at least one.
- all: every highlight; every document with a highlight or a note.
- Image highlights are always loaded; the renderer drops them when `includeImages` is false.

## Format (group by document)
```
# StudyReader – {scopeName}
<blank>
_Exported {yyyy-MM-dd HH:mm} · {N} highlight(s) from {M} document(s)_
```
then, per document (only if it renders at least one highlight or a document note):
```
<blank>
## {title}
<blank>
_{author} · {categoryName}_            (author empty → _{categoryName}_)
<blank>
### Document note                       (only if includeDocumentNotes and documentNote != nil)
<blank>
{documentNote lines}
<blank>
### Highlights                          (only if the document renders ≥ 1 highlight)
<blank>
- **{label}** · p. {pageIndex + 1}      (" · p. N" omitted when pageIndex is nil)
  {body lines, each prefixed by 2 spaces; blank lines stay empty}
  - Note: {first note line}             (only if includeNotes and note non-empty; later lines prefixed by 4 spaces)
  - Tags: #{name} #{name}               (only if tagNames non-empty)
<blank between highlights>
```
- `{label}` = `colorLabels[color.rawValue]`. Image highlight body = `[Image highlight, page {pageIndex + 1}]`.
- N = rendered highlights; M = rendered document sections. "1 highlight", "2 highlights", "1 document", "0 documents".
- Date: `yyyy-MM-dd HH:mm`, `en_US_POSIX`, the given time zone.

Group by tag: after the header, one section per tag name (case-insensitive order) `## #{tag}` with its highlights (document title, then positionKey), each item ending with a blank line and `  _— {title}, p. {page}_` (", p. N" omitted without a page); no "Tags:" line. Untagged highlights last under `## Untagged`. Then, if includeDocumentNotes and any document note exists, `## Document notes` with `### {title}` + note per document (title order). N counts each highlight once; M = documents with at least one rendered highlight or note.

## Golden files (exact content; `content` built in the test, `generatedAt` = 2026-10-24 14:05 UTC, `timeZone` UTC, default labels)
Test content: scopeName "ML1 Lecture 3"; one document "Lecture 3: Gradient Descent", author "Ada Lovelace", category "Lecture slides", note "Exam covers sections 2–4."; highlights (positionKey order): h1 yellow, pageIndex 0, body `The **gradient** points uphill.`, note "Negate it to descend.", tags ["exam", "ml"]; h2 blue image, pageIndex 2, no note, no tags; h3 green, pageIndex 4, body `Learning rate *η*`, note "Line one\n\nLine two", tags ["ml"].

`by-document-all-options.md` (default `ExportOptions()`):
```markdown
# StudyReader – ML1 Lecture 3

_Exported 2026-10-24 14:05 · 3 highlights from 1 document_

## Lecture 3: Gradient Descent

_Ada Lovelace · Lecture slides_

### Document note

Exam covers sections 2–4.

### Highlights

- **Key concept** · p. 1
  The **gradient** points uphill.
  - Note: Negate it to descend.
  - Tags: #exam #ml

- **Connection** · p. 3
  [Image highlight, page 3]

- **Exam** · p. 5
  Learning rate *η*
  - Note: Line one

    Line two
  - Tags: #ml
```
`by-tag-all-options.md` (`groupBy: .tag`):
```markdown
# StudyReader – ML1 Lecture 3

_Exported 2026-10-24 14:05 · 3 highlights from 1 document_

## #exam

- **Key concept** · p. 1
  The **gradient** points uphill.
  - Note: Negate it to descend.

  _— Lecture 3: Gradient Descent, p. 1_

## #ml

- **Key concept** · p. 1
  The **gradient** points uphill.
  - Note: Negate it to descend.

  _— Lecture 3: Gradient Descent, p. 1_

- **Exam** · p. 5
  Learning rate *η*
  - Note: Line one

    Line two

  _— Lecture 3: Gradient Descent, p. 5_

## Untagged

- **Connection** · p. 3
  [Image highlight, page 3]

  _— Lecture 3: Gradient Descent, p. 3_

## Document notes

### Lecture 3: Gradient Descent

Exam covers sections 2–4.
```
`by-document-minimal.md` (`includeNotes: false, includeDocumentNotes: false, includeImages: false`):
```markdown
# StudyReader – ML1 Lecture 3

_Exported 2026-10-24 14:05 · 2 highlights from 1 document_

## Lecture 3: Gradient Descent

_Ada Lovelace · Lecture slides_

### Highlights

- **Key concept** · p. 1
  The **gradient** points uphill.
  - Tags: #exam #ml

- **Exam** · p. 5
  Learning rate *η*
  - Tags: #ml
```
`empty.md` (scopeName "All highlights", no documents):
```markdown
# StudyReader – All highlights

_Exported 2026-10-24 14:05 · 0 highlights from 0 documents_
```
Each golden file ends with one newline after its last line. Load them with `Bundle(for:)` subdirectory `Fixtures/golden/export` (like `MarkdownFixtures`).

## Tests
`ExportRendererTests` (SPEC F-21 AC1): `byDocumentAllOptions`, `byTagAllOptions`, `byDocumentMinimal`, `emptyScope` (compare with the goldens byte for byte); `includesNotes` (SPEC F-09 AC2: the highlight note and the document note appear with default options and disappear with them off); `editedTextWins` (an `ExportHighlight` built by the repository from a highlight with `editedText` "Edited *x*" renders `Edited \*x\*`); `documentsOrderedByTitle` (two documents "b", "A" → "A" first); `noTrailingSpacesOrDoubleBlankLines` (property check over all outputs).
`ExportRepositoryTests` (in-memory): `scopeNames`; `documentScope`, `tagScope`, `categoryScope` (documents with only a note included), `themedReviewScope` (tags all + colors), `allScope`; `selectionContent` (only the given ids); `targetsCRUD` (insert, `target(for:)`, `updateOptions`, `setKeepInSync`, `recordResult` writes only the given columns — `lastExportedAt` stored as REAL —, `clearFileId`, `removeTarget`); `changeTokenEmits` (`.timeLimit(.minutes(1))`: a highlight note change emits). Writing tests end with `FTSIntegrity.check`.
`DriveFolderLinkTests`: each accepted form → the ID; `https://example.com/folders/x`, `"short"`, `""` → nil.

## Acceptance criteria
1. The renderer produces the exact Markdown for each grouping and option. → tests `ExportRendererTests/*` (SPEC F-21 AC1)
2. Notes are included and can be turned off. → test `ExportRendererTests/includesNotes` (SPEC F-09 AC2)
3. Scopes load the right highlights, documents and notes; targets persist with column-limited updates. → tests `ExportRepositoryTests/*`
4. Folder links parse. → tests `DriveFolderLinkTests/*`

## Out of scope
- Network, sign-in, UI, sync (T71–T74). HTML conversion (T71).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
