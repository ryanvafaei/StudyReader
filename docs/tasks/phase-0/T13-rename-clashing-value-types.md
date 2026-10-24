# T13: Rename `CardState` and `Anchor` to avoid module clashes

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L6)
- **Agent:** data-layer
- **Depends on:** T12
- **ADRs:** docs/decisions/0012-data-layer-conventions.md ("Column value types that would clash" bullet)
- **Visual check needed:** no

## Goal
`CardState` clashes with `FSRS.CardState` and `Anchor` clashes with `SwiftUI.Anchor`. A file that imports both modules can't name the type ("ambiguous for type lookup"). Rename the Swift types to `ReviewCardState` and `HighlightAnchor` before Phase 1 and 2 code depends on them. This is a pure rename: SQL values, raw values and JSON stay exactly the same. Add a compile-time guard test.

## Files to touch
- `StudyReader/Core/Models/ModelEnums.swift` (modify: `CardState` → `ReviewCardState`)
- `StudyReader/Core/Models/ReviewCard.swift` (modify: `var state: ReviewCardState`)
- `StudyReader/Core/Models/Anchor.swift` (modify: `enum Anchor` → `enum HighlightAnchor`, doc comment. Keep the file name.)
- `StudyReader/Core/Models/Highlight.swift` (modify: `var anchor: HighlightAnchor`)
- `StudyReaderTests/Support/TestData.swift` (modify: `state: ReviewCardState = .new`)
- `StudyReaderTests/CoreTests/ModelEnumTests.swift` (modify)
- `StudyReaderTests/CoreTests/AnchorCodingTests.swift` (modify: type name only; keep the file and struct names)
- `StudyReaderTests/CoreTests/RecordRoundTripTests.swift` (modify: `Anchor.pdf(` → `HighlightAnchor.pdf(`)
- `StudyReaderTests/CoreTests/NameClashTests.swift` (new)

## Steps
1. Search `StudyReader/` and `StudyReaderTests/` for the whole words `CardState` and `Anchor` (regex `\bCardState\b`, `\bAnchor\b`). At planning time, the matches were exactly the files above. Rename every use of the type. Don't rename:
   - `PDFAnchor`, `TextAnchor`, `ImageAnchor`, `AnchorStatus`, `anchorStatus`, or the `anchor` property;
   - the private `Kind` enum or the `CodingKeys` inside the anchor type, because the JSON `type` values `pdf`/`text`/`image` must stay;
   - comments that use "anchor" as an English word.
2. The doc comment on the enum becomes: `/// Stored as JSON in highlight.anchor. Encodes as {"type": "<case>", "<case>": {...}}. Named HighlightAnchor to avoid SwiftUI.Anchor (ADR-0012).`
3. The doc comment on the enum in ModelEnums.swift becomes: `/// reviewCard.state (copy of FSRS state). Named ReviewCardState to avoid FSRS.CardState (ADR-0012).`
4. Add `NameClashTests.swift`, exactly these imports, in this order:
   ```swift
   import Foundation
   import GRDB
   import Markdown
   import FSRS
   import SwiftUI
   import Testing
   @testable import StudyReader
   ```
   `@Suite struct NameClashTests` with:
   - `appTypesResolveUnqualified`: declare `let types: [Any.Type] = [...]` listing, unqualified: `LibraryDocument`, `DocumentCategory`, `DocumentText`, `Highlight`, `LibraryTag`, `HighlightTag`, `DocumentTag`, `DocumentNote`, `ReviewCard`, `ReviewLogEntry`, `ThemedReview`, `ExportTarget`, `HighlightEmbedding`, `HighlightAnchor`, `PDFAnchor`, `TextAnchor`, `ImageAnchor`, `ReviewCardState`, `CardType`, `HighlightColor`, `ReviewFrequency`. Then `#expect(types.count == 21)`. The test exists so that this file compiles.
   - `renamedTypesKeepStoredValues`: `#expect(ReviewCardState.allCases.map(\.rawValue) == ["new", "learning", "review", "relearning"])`. Encode `HighlightAnchor.text(TextAnchor(start: 1, length: 2, text: "ab", prefix: "", suffix: "", sourceVersion: 1))` with `JSONEncoder`, parse it with `JSONSerialization`, and expect `root["type"] as? String == "text"` and `root.keys.sorted() == ["text", "type"]`.
   If any listed type is ambiguous in this file, don't rename it and don't drop it from the list. Report BLOCKED with the compiler error.

## Interfaces to produce
```swift
enum ReviewCardState: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible { case new, learning, review, relearning }
enum HighlightAnchor: Codable, Sendable, Equatable { case pdf(PDFAnchor), text(TextAnchor), image(ImageAnchor) }   // JSON unchanged
```
`ReviewCard.state: ReviewCardState`, `Highlight.anchor: HighlightAnchor`. No typealiases for the old names.

## Acceptance criteria
1. No Swift file in `StudyReader/` or `StudyReaderTests/` contains the type names `CardState` or `Anchor` as whole words, except inside `FSRS.`-qualified references (none expected). → reviewer greps `\bCardState\b` and `\bAnchor\b`.
2. A file importing SwiftUI, FSRS, Markdown, GRDB and Testing names every record and value type unqualified. → test `NameClashTests/appTypesResolveUnqualified`
3. Raw values and the anchor JSON shape are unchanged. → tests `NameClashTests/renamedTypesKeepStoredValues`, `AnchorCodingTests/pdfAnchorJSONShape`, `AnchorCodingTests/decodesTextAnchorLiteral`, `ModelEnumTests/rawValuesMatchSchema`
4. Records still round-trip. → `RecordRoundTripTests` (all tests) and `ReviewExportRecordTests` pass unchanged apart from the rename.
5. The full suite passes with no new warnings.

## Out of scope
- Renaming `Anchor.swift`, `AnchorCodingTests.swift`, `AnchorStatus` or any SQL or JSON name.
- Editing old task specs (T03, T05, T06). They are history.
- Any other bug-hunt finding.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
