---
name: model-value-types-notes
description: Locations and pitfalls for column enums, Anchor, and JSON column value types (T03) in StudyReader
metadata:
  type: reference
---

- `Core/Models/ModelEnums.swift` (column enums, `DatabaseValueConvertible`), `Core/Models/Anchor.swift` (CGRectCodable, PDFAnchor, TextAnchor, ImageAnchor, Anchor), `Core/Models/ColumnValues.swift` (PDFPosition, TextRun, ThemedReviewFilter, ReviewInterval, ExportScope, ExportOptions).
- Anchor's `Kind` must decode from `String`, not from the enum itself: decoding the enum directly throws GRDB-style `dataCorrupted` without the required "Unknown anchor type" description.
- Defaulting decoders: a custom `init(from:)` disables the synthesized memberwise init, so the explicit init from the spec is required on those types.
- Test files: `StudyReaderTests/CoreTests/{ModelEnumTests,AnchorCodingTests,ColumnValuesTests}.swift`. Test helper `jsonObject` uses `JSONSerialization`; `#require` must wrap a non-throwing expression (`let x = try ...; try #require(x as? ...)`).
- T03 suite: 9 tests in 3 suites, all passing.
