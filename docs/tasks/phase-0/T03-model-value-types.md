# T03: Model value types: column enums, Anchor, JSON column values

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T01
- **ADRs:** docs/decisions/0004-highlight-anchoring.md, docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Define the `Codable` value types the database records (T05, T06) store in enum and JSON columns, with stable, tested encodings. Part of epic E0.2. Every later phase reads and writes these shapes, so names and JSON keys must match exactly.

Read first: ARCHITECTURE §4 (CHECK constraints and JSON column comments) and §5 (Anchor), ADR-0012.

## Files to touch
- `StudyReader/Core/Models/ModelEnums.swift` (new)
- `StudyReader/Core/Models/Anchor.swift` (new)
- `StudyReader/Core/Models/ColumnValues.swift` (new)
- `StudyReaderTests/CoreTests/ModelEnumTests.swift` (new)
- `StudyReaderTests/CoreTests/AnchorCodingTests.swift` (new)
- `StudyReaderTests/CoreTests/ColumnValuesTests.swift` (new)

## Interfaces to produce

### ModelEnums.swift (`import Foundation`, `import GRDB`)
Every enum below: `String` raw value (except `HighlightColor`), `Codable, Sendable, CaseIterable, DatabaseValueConvertible`. Raw values must equal the SQL CHECK values exactly.

```swift
enum FileType: String          { case pdf, markdown }
enum CoverSource: String       { case automatic = "default", custom, page }
enum ExtractionStatus: String  { case pending, done, failed }
enum HighlightKind: String     { case text, image }
enum ReaderViewKind: String    { case pdf, text, markdown }          // highlight.view
enum AnchorStatus: String      { case ok, orphaned }
enum ReviewFrequency: String   { case off, low, normal, high }       // category.frequency, reviewCard.frequencyOverride
enum CardType: String          { case passive, cloze, qa }
enum CardState: String         { case new, learning, review, relearning }   // reviewCard.state (copy of FSRS state)
enum SuspendedReason: String   { case mastery, frequencyOff, user }
enum ReviewSessionKind: String { case daily, themed }
enum ReviewOrderMode: String   { case dueFirst, random }
enum ExportFormat: String      { case markdown, html }

/// highlight.color 0–4 (SPEC F-06). Labels are UI/Settings (Phase 1), not here.
enum HighlightColor: Int, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case yellow = 0, green = 1, blue = 2, pink = 3, purple = 4
}
```

### Anchor.swift (`import Foundation`, `import CoreGraphics`)
```swift
/// Stable JSON shape {"x","y","width","height"} (CGRect's own Codable uses nested arrays).
struct CGRectCodable: Codable, Sendable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    init(x: Double, y: Double, width: Double, height: Double)
    init(_ rect: CGRect)
    var cgRect: CGRect { get }
}

struct PDFAnchor: Codable, Sendable, Equatable {
    struct PageRects: Codable, Sendable, Equatable {
        var pageIndex: Int
        var rects: [CGRectCodable]      // PDF page space, one per line (ARCHITECTURE §5.1)
    }
    var pages: [PageRects]
    var text: String
    var prefix: String                  // up to 32 chars before
    var suffix: String                  // up to 32 chars after
}

struct TextAnchor: Codable, Sendable, Equatable {
    var start: Int                      // UTF-16 offset
    var length: Int                     // UTF-16 length
    var text: String
    var prefix: String
    var suffix: String
    var sourceVersion: Int
}

struct ImageAnchor: Codable, Sendable, Equatable {
    var pageIndex: Int
    var rect: CGRectCodable
}

enum Anchor: Codable, Sendable, Equatable {
    case pdf(PDFAnchor)
    case text(TextAnchor)
    case image(ImageAnchor)
}
```
`Anchor` has a hand-written `Codable` implementation (not the synthesized one). JSON shape:
- `.pdf(a)` → `{"type": "pdf", "pdf": <a>}`
- `.text(a)` → `{"type": "text", "text": <a>}`
- `.image(a)` → `{"type": "image", "image": <a>}`

Implement with `private enum CodingKeys: String, CodingKey { case type, pdf, text, image }` and `private enum Kind: String, Codable { case pdf, text, image }`. Decoding: read `type`, then decode the payload under the key of the same name. An unknown `type` throws `DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown anchor type")`.

Note: SwiftUI also has a type named `Anchor`. Inside the app module ours wins. Test files must not `import SwiftUI` together with `@testable import StudyReader`, or must write `StudyReader.Anchor`.

### ColumnValues.swift (`import Foundation`)
All `Codable, Sendable, Equatable`. Inner enums are `String, Codable, Sendable, CaseIterable`.

```swift
/// document.pdfPosition
struct PDFPosition: Codable, Sendable, Equatable {
    var pageIndex: Int
    var offsetY: Double
}

/// documentText.runs element; offsets relative to that row's text (ARCHITECTURE §6 step 9)
struct TextRun: Codable, Sendable, Equatable {
    var start: Int
    var length: Int
    var bold: Bool
    var italic: Bool
    var mono: Bool
    var link: String?
}

enum TagMatchMode: String, Codable, Sendable, CaseIterable { case any, all }

/// themedReview.filter
struct ThemedReviewFilter: Codable, Sendable, Equatable {
    var tagIds: [String] = []
    var tagMode: TagMatchMode = .any
    var documentIds: [String] = []
    var categoryIds: [String] = []
    var colors: [HighlightColor] = []      // encodes as ints
    init(tagIds: [String] = [], tagMode: TagMatchMode = .any, documentIds: [String] = [],
         categoryIds: [String] = [], colors: [HighlightColor] = [])
    // Custom init(from:) using decodeIfPresent(...) ?? default for every key.
}

/// themedReview.interval
struct ReviewInterval: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable, CaseIterable { case daily, everyNDays, weekdays }
    var kind: Kind
    var n: Int?               // kind == .everyNDays only
    var weekdays: [Int]?      // kind == .weekdays only; Calendar weekday numbers 1 = Sunday … 7 = Saturday
    static let daily: ReviewInterval                              // ReviewInterval(kind: .daily, n: nil, weekdays: nil)
    static func everyNDays(_ n: Int) -> ReviewInterval
    static func weekdays(_ days: [Int]) -> ReviewInterval
}

/// exportTarget.scope
struct ExportScope: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable, CaseIterable { case document, tag, category, themedReview, all }
    var kind: Kind
    var id: String?           // nil only for .all
    static let all: ExportScope
    static func document(_ id: String) -> ExportScope
    static func tag(_ id: String) -> ExportScope
    static func category(_ id: String) -> ExportScope
    static func themedReview(_ id: String) -> ExportScope
}

enum ExportGroupBy: String, Codable, Sendable, CaseIterable { case document, tag }

/// exportTarget.options (SPEC F-21 defaults)
struct ExportOptions: Codable, Sendable, Equatable {
    var includeNotes: Bool = true
    var includeDocumentNotes: Bool = true
    var includeImages: Bool = true
    var groupBy: ExportGroupBy = .document
    init(includeNotes: Bool = true, includeDocumentNotes: Bool = true,
         includeImages: Bool = true, groupBy: ExportGroupBy = .document)
    // Custom init(from:) using decodeIfPresent(...) ?? default for every key.
}
```
Optional properties use the synthesized `encodeIfPresent` behaviour (nil keys are omitted). Don't add any other types or helpers.

## Acceptance criteria
1. Every enum's `allCases.map(\.rawValue)` equals the ARCHITECTURE §4 CHECK list in declaration order (e.g. `CoverSource` → `["default","custom","page"]`, `HighlightColor` → `[0,1,2,3,4]`). → test `ModelEnumTests/rawValuesMatchSchema`
2. Each `Anchor` case round-trips through `JSONEncoder`/`JSONDecoder` unchanged. → test `AnchorCodingTests/roundTripAllCases`
3. Encoded `.pdf` anchor, parsed with `JSONSerialization`, has top-level keys exactly `["pdf","type"]` (sorted), `type == "pdf"`, and each rect has keys exactly `["height","width","x","y"]`. → test `AnchorCodingTests/pdfAnchorJSONShape`
4. This literal decodes to `.text(TextAnchor(start: 10, length: 5, text: "hello", prefix: "say ", suffix: " world", sourceVersion: 1))`:
   `{"type":"text","text":{"start":10,"length":5,"text":"hello","prefix":"say ","suffix":" world","sourceVersion":1}}` → test `AnchorCodingTests/decodesTextAnchorLiteral`
5. `{"type":"bogus"}` throws `DecodingError`. → test `AnchorCodingTests/unknownTypeThrows`
6. `CGRectCodable(CGRect(x: 1.5, y: 2, width: 3, height: 4)).cgRect` equals the original rect. → test `AnchorCodingTests/cgRectCodableConverts`
7. `ExportOptions` and `ThemedReviewFilter` decoded from `{}` equal their defaults. → test `ColumnValuesTests/missingKeysUseDefaults`
8. `ReviewInterval.everyNDays(3)` encodes without a `weekdays` key; `ExportScope.all` encodes without an `id` key; `ThemedReviewFilter(colors: [.blue])` encodes `colors` as `[2]`. → test `ColumnValuesTests/encodedShapes`
9. `PDFPosition`, `TextRun` (with and without `link`), `ReviewInterval`, `ExportScope`, `ExportOptions`, `ThemedReviewFilter` round-trip. → test `ColumnValuesTests/roundTrips`

## Out of scope
- GRDB records (T05, T06), database schema (T04).
- Color labels/palette, anchor creation from PDFKit selections, re-anchoring logic (Phase 1+).

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
