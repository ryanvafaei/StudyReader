# T42: PDFTextExtractor (search text now, text view in Phase 3)

- **Phase:** 1 (E1.6 needs per-page PDF text for F-12; the same extractor feeds the Phase 3 text view, F-05)
- **Agent:** pdf-engine
- **Depends on:** none
- **ADRs:** docs/decisions/0009-pdf-text-extraction-heuristics.md, ARCHITECTURE §6 (read in full; rule 5 was amended for backlog L3), §3 (threading)
- **Visual check needed:** no

## Goal
Turn a PDF into one normalized text string per page, with bold/italic/monospace/link runs, following ARCHITECTURE §6: line normalization, bullets, repeated header/footer removal, hyphenation and soft line-break joining, and the L3 rule for soft hyphens at line ends. Search indexes these strings (T44, T65); text anchors in Phase 3 use their UTF-16 offsets, so the output must be deterministic.

## Files to touch
- `StudyReader/Features/Extraction/PDFTextExtractor.swift` (new)
- `StudyReaderTests/ExtractionTests/TextExtractionTests.swift` (new)
- `docs/bugs/backlog.md` (modify: remove L3, "fixed by T42 (ARCHITECTURE §6 rule 5 amended)")

## Interfaces to produce
```swift
struct ExtractedPage: Sendable, Equatable {
    var pageIndex: Int
    var text: String            // §6 output for this page; "" for pages without text
    var runs: [TextRun]         // TextRun (ColumnValues.swift); offsets are UTF-16 within `text`; only runs with
                                // bold, italic, mono or link set; adjacent runs with identical attributes merged
}
enum PDFTextExtractionError: Error, Equatable { case cannotOpen, locked }

enum PDFTextExtractor {
    /// Bump when output text changes (ARCHITECTURE §6); stored in document.extractionVersion.
    static let version = 1
    /// Opens its own PDFDocument(url:) (never pass PDFKit objects in or out). Callable off the main actor.
    static func extract(fileAt url: URL) throws -> [ExtractedPage]
    /// The text-only pipeline (§6 steps 1–8) over raw page strings, for tests without PDFKit and for reuse.
    static func process(rawPages: [String]) -> [String]
    /// The joined text-view string: pages joined with "\n\n".
    static func joinedText(_ pages: [ExtractedPage]) -> String
    /// UTF-16 start offset of each page in joinedText (page i = sum of previous page lengths + 2 * i).
    static func startOffsets(_ pages: [ExtractedPage]) -> [Int]
}
```
Rules (ARCHITECTURE §6, restated precisely):
1. Per page: `page.attributedString` (fall back to `page.string`, then ""). Normalize `\r\n`/`\r` to `\n`, collapse runs of spaces/tabs to one space, NFC.
2. Lines = split by `\n`, each trimmed; empty lines are paragraph breaks.
3. Bullet lines start with `•`, `▪`, `◦`, `–`, `-`, `*` followed by a space, or match `^\d+[.)]\s`. They start a new paragraph. Symbol bullets are rewritten to `• ` + rest; numbered bullets keep their number (`1. First step`).
4. Headers/footers: for each page, the first 2 and last 2 non-empty lines are candidates. Digit-normalize (every digit → `#`). A line is a candidate on a page only if its normalized form occurs exactly once among that page's non-empty lines (amended 2026-10-24 after T42: otherwise body lines like "Body text on page N, line 1." would match). A normalized candidate that appears on ≥ 50 % of pages and on at least 3 pages is removed from every page where it appears as a candidate. Known limitation: on very short pages, a body line near the top or bottom that differs across pages only by digits can still be removed. Lone page-number lines (`^\d+$`, `^Page \d+( of \d+)?$`, `^\d+ / \d+$`, case-insensitive) are removed everywhere.
5. Joining within a page: a line ending in U+00AD → joined to the next line without the U+00AD, always. A line ending in `-` or U+2010 whose next line starts with a lowercase letter → joined without the hyphen. A line not ending in `.?!:;` whose next line starts lowercase → joined with one space. Otherwise → paragraph break `\n\n`. Bullet lines never join with the previous line.
6. Page text = paragraphs joined with `\n\n`, no leading/trailing whitespace.
7. Runs: map attributed-string font traits (bold via `NSFontDescriptor.SymbolicTraits.bold`, italic via `.italic`, monospace via `.monoSpace` or a fixed-pitch font) and `.link` to the output text. Track offsets through the transformations (keep a mapping from output UTF-16 offsets to source offsets while building lines), so each run covers exactly the output characters that came from styled source characters.

## Tests (`TextExtractionTests`)
Fixtures from `PDFFixtureBuilder`, written with `writeTemporary`.
- `joinsHyphenation` (SPEC F-05 AC1): `hyphenated()` → page 0 text == `"The algorithm uses gradient descent to minimize the loss function.\n\nNext paragraph starts here."`.
- `removesRepeatedHeaders` (SPEC F-05 AC1): `repeatedHeaderFooter(pageCount: 6)` → no page contains `PDFFixtureBuilder.headerText` or `"Page "` + digit; each page contains `"Body text on page \(n), line 1."`.
- `joinsSoftHyphenAtLineEnd` (backlog L3): `process(rawPages: ["The photo\u{00AD}\nsynthesis rate", "Photo\u{00AD}\nSynthesis"])` → `["The photosynthesis rate", "PhotoSynthesis"]`. Also with U+2010: `"gradi\u{2010}\nent"` → `"gradient"`.
- `keepsBullets`: `slideBullets()` → contains `"• Supervised learning\n\n• Unsupervised learning\n\n• Clustering\n\n1. First step\n\n2) Second step"`.
- `twoColumnIsDeterministic`: `twoColumn()` extracted twice gives equal output, and contains "Left column line 1." and "Right column line 1.".
- `richRunsMarkBoldItalicMono`: `richRuns()` → page text == `PDFFixtureBuilder.richRunsText`; runs include bold over "bold", italic over "italic", mono over "code" (compare by substring of `text` using each run's UTF-16 range).
- `offsetsAndJoin`: `startOffsets` for pages of lengths 5, 0, 3 (UTF-16) → `[0, 7, 9]`; `joinedText` == `"aaaaa\n\n\n\nbbb"`.
- `lockedAndDamaged`: `encrypted()` → throws `.locked`; `damaged()` → `.cannotOpen`.
- `searchSampleSoftHyphen`: after extraction-like processing of `SearchSamples.photosynthesisSoftHyphen` inside a line (`"x photo\u{00AD}synthesis y"`) the U+00AD is kept (only line-end soft hyphens are joined; the tokenizer handles in-word ones).

## Acceptance criteria
1. Hyphenation is joined and repeated headers/footers are removed. → tests `TextExtractionTests/joinsHyphenation`, `removesRepeatedHeaders`
2. Soft hyphens and U+2010 at line ends are joined (L3). → test `TextExtractionTests/joinsSoftHyphenAtLineEnd`
3. Bullets, runs, offsets and error cases behave as specified. → tests `keepsBullets`, `richRunsMarkBoldItalicMono`, `offsetsAndJoin`, `lockedAndDamaged`, `twoColumnIsDeterministic`, `searchSampleSoftHyphen`
4. L3 removed from the backlog.

## Out of scope
- Writing `documentText` rows and scheduling (T44). The text view (Phase 3). Vision OCR.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. 15 TextExtraction tests run and pass; 267 total. Rule 4 deviation accepted (ARCHITECTURE section 6 rule 4 and spec wording to be amended). Minor: thin coverage for runs surviving joins, link runs, non-BMP offsets, all-lines-removed page.
