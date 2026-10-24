---
name: model-value-types-notes
description: Locations and pitfalls for column enums, HighlightAnchor, and JSON column value types (T03, renamed T13) in StudyReader
metadata:
  type: reference
---

- `Core/Models/ModelEnums.swift` (column enums, `DatabaseValueConvertible`; `ReviewCardState` since T13, was `CardState`), `Core/Models/Anchor.swift` (file name kept; CGRectCodable, PDFAnchor, TextAnchor, ImageAnchor, `HighlightAnchor` since T13, was `Anchor`), `Core/Models/ColumnValues.swift` (PDFPosition, TextRun, ThemedReviewFilter, ReviewInterval, ExportScope, ExportOptions).
- Names `CardState` and `Anchor` clash with `FSRS.CardState` and `SwiftUI.Anchor`. Never reintroduce them. `StudyReaderTests/CoreTests/NameClashTests.swift` imports FSRS and SwiftUI and lists app types unqualified, so it fails to compile if a clash returns.
- Anchor's `Kind` must decode from `String`, not from the enum itself: decoding the enum directly throws GRDB-style `dataCorrupted` without the required "Unknown anchor type" description.
- Defaulting decoders: a custom `init(from:)` disables the synthesized memberwise init, so the explicit init from the spec is required on those types.
- Test files: `StudyReaderTests/CoreTests/{ModelEnumTests,AnchorCodingTests,ColumnValuesTests,NameClashTests}.swift`. Test helper `jsonObject` uses `JSONSerialization`; `#require` must wrap a non-throwing expression (`let x = try ...; try #require(x as? ...)`).
- T03 suite: 9 tests in 3 suites, all passing. T13 rename kept all test names and JSON shape.
