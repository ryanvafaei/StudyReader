# T09: PDFFixtureBuilder (generated test PDFs)

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T01
- **ADRs:** none (ARCHITECTURE §15)
- **Visual check needed:** no

## Goal
A test-only builder that generates PDFs with Core Graphics + Core Text, so later tests (import, extraction, anchors, rich text, snapshots, metadata defaults) never need committed binary PDFs. Epic E0.3. The builder draws every text line at an explicit position, so line breaks, headers, and hyphenation are exactly controlled.

Read first: ARCHITECTURE §15 (PDFFixtureBuilder bullet), SPEC F-02 (encrypted/damaged PDFs), F-05 AC1, F-07 AC2, F-08 AC1, F-11. No reference repos.

## Files to touch
- `StudyReaderTests/Support/PDFFixtureBuilder.swift` (new)
- `StudyReaderTests/SupportTests/PDFFixtureBuilderTests.swift` (new)

## Interfaces to produce (all in the test target)

```swift
import CoreGraphics
import CoreText
import Foundation

enum FixtureFont: Sendable, CaseIterable {
    case regular, bold, italic, boldItalic, mono
    /// "Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique", "Menlo-Regular"
    var postScriptName: String { get }
}

struct FixtureRun: Sendable, Equatable {
    var text: String
    var font: FixtureFont = .regular
    init(_ text: String, font: FixtureFont = .regular)
}

enum FixtureElement: Sendable {
    /// One line of text. `origin` is the baseline start in PDF page space (points, origin bottom-left).
    case line([FixtureRun], origin: CGPoint, fontSize: CGFloat)
    /// Filled rectangle in page space, RGB 0...1.
    case filledRect(CGRect, red: CGFloat, green: CGFloat, blue: CGFloat)
}

struct FixturePage: Sendable {
    var elements: [FixtureElement]
    init(_ elements: [FixtureElement])
}

struct PDFFixtureOptions: Sendable {
    var pageSize: CGSize = CGSize(width: 612, height: 792)   // US Letter portrait
    var title: String? = nil
    var author: String? = nil
    var userPassword: String? = nil
    var ownerPassword: String? = nil
    init(pageSize: CGSize = CGSize(width: 612, height: 792), title: String? = nil, author: String? = nil,
         userPassword: String? = nil, ownerPassword: String? = nil)
}

enum PDFFixtureBuilder {
    // MARK: Core
    /// Draws each page into a CGContext(consumer:mediaBox:auxiliaryInfo:) PDF context backed by NSMutableData.
    /// auxiliaryInfo: kCGPDFContextTitle, kCGPDFContextAuthor, kCGPDFContextUserPassword,
    /// kCGPDFContextOwnerPassword when set (owner defaults to user password if only user is set).
    /// Each page: beginPDFPage(nil); fill the page white; draw elements in order; endPDFPage(). Then closePDF().
    static func makePDF(pages: [FixturePage], options: PDFFixtureOptions = PDFFixtureOptions()) -> Data

    /// Consecutive single-run lines, top to bottom: line i baseline at (x, topY - i * lineHeight).
    static func lines(_ texts: [String], font: FixtureFont = .regular, fontSize: CGFloat = 12,
                      x: CGFloat = 72, topY: CGFloat = 720, lineHeight: CGFloat = 16) -> [FixtureElement]

    /// Writes data to FileManager.default.temporaryDirectory/PDFFixtures/<UUID>/<name> and returns the URL.
    static func writeTemporary(_ data: Data, name: String) throws -> URL

    // MARK: Presets (content constants below are part of the interface; later tests assert on them)
    static func plainMultiPage(pageCount: Int = 5) -> Data
    static func twoColumn() -> Data
    static func repeatedHeaderFooter(pageCount: Int = 6) -> Data
    static func richRuns() -> Data
    static func hyphenated() -> Data
    static func slideBullets() -> Data
    static func coloredRegion() -> Data
    static func withMetadata(title: String, author: String) -> Data
    static func encrypted(password: String = "secret") -> Data
    static func damaged() -> Data
}
```

### Drawing a line
Build an `NSAttributedString` from the runs with attributes
`[NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(name as CFString, fontSize, nil),
  NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]`,
then `let line = CTLineCreateWithAttributedString(attr)`, `context.textMatrix = .identity`, `context.textPosition = origin`, `CTLineDraw(line, context)`. Keep all CG/CT objects local to the function (they aren't Sendable).

### Preset content (exact)
| Preset | Page size | Content |
|---|---|---|
| `plainMultiPage(n)` | 612×792 | page p (1-based) has 10 lines via `lines`: `"Page \(p) line \(l): The quick brown fox jumps over the lazy dog."` for l = 1…10 |
| `twoColumn()` | 612×792 | 1 page. Left column x = 72: `"Left column line \(i)."`; right column x = 330: `"Right column line \(i)."`, i = 1…12, same baselines (topY 720, lineHeight 16), font size 11 |
| `repeatedHeaderFooter(n)` | 612×792 | every page: header `headerText` at (72, 750) size 10; body lines `"Body text on page \(p), line \(l)."` l = 1…5 starting topY 700; footer `"Page \(p) of \(n)"` at (72, 40) size 10 |
| `richRuns()` | 612×792 | 1 line at (72, 720) size 14: runs `"a "` regular, `"bold"` bold, `" and "` regular, `"italic"` italic, `" word with "` regular, `"code"` mono |
| `hyphenated()` | 612×792 | lines (regular, from topY 720): `hyphenatedLines` |
| `slideBullets()` | 792×612 (landscape) | title `"Key Ideas"` bold size 28 at (60, 540); then `slideBulletLines` size 20 from topY 480, lineHeight 32, x 60 |
| `coloredRegion()` | 612×792 | `filledRect(coloredRect, red: 1, green: 0, blue: 0)` and line `"Figure 1: red box"` at (100, 80) size 12 |
| `withMetadata(t, a)` | 612×792 | 1 page, line `"Metadata fixture"`; options title t, author a |
| `encrypted(pw)` | 612×792 | 1 page, line `"Encrypted fixture"`; userPassword = ownerPassword = pw |
| `damaged()` | n/a | `Data("%PDF-1.7\n%StudyReader damaged fixture\n1 0 obj\n<<".utf8)` (truncated, not a valid PDF) |

```swift
extension PDFFixtureBuilder {
    static let headerText = "Introduction to Machine Learning — Lecture 3"
    static let richRunsText = "a bold and italic word with code"
    static let hyphenatedLines = ["The algorithm uses gradi-", "ent descent to minimize the",
                                  "loss function.", "Next paragraph starts here."]
    static let slideBulletLines = ["• Supervised learning", "• Unsupervised learning", "– Clustering",
                                   "1. First step", "2) Second step"]
    static let coloredRect = CGRect(x: 100, y: 100, width: 200, height: 150)
}
```

## Acceptance criteria
Tests open the data with `PDFDocument(data:)` (`import PDFKit`) and normalize `page.string` line endings (`\r\n` and `\r` → `\n`) before comparing.
1. `plainMultiPage()` has 5 pages; page 3's string contains `"Page 3 line 7: The quick brown fox"`. → test `PDFFixtureBuilderTests/plainMultiPageHasPagesAndText`
2. `twoColumn()` page text contains `"Left column line 12."` and `"Right column line 12."`. → test `PDFFixtureBuilderTests/twoColumnContainsBothColumns`
3. Every page of `repeatedHeaderFooter()` contains `headerText` and `"Page \(p) of 6"`. → test `PDFFixtureBuilderTests/repeatedHeaderOnEveryPage`
4. In `richRuns()`, `page.attributedString` contains `richRunsText`; the font over `"bold"` has the bold trait (`NSFontDescriptor.SymbolicTraits.bold`) or a name containing "Bold"; over `"italic"` the italic trait or a name containing "Oblique"/"Italic"; over `"code"` the monospace trait or a name containing "Menlo". → test `PDFFixtureBuilderTests/richRunsKeepFontTraits`. If PDFKit reports no usable font information, don't weaken the test: report BLOCKED with what `attributedString` contains.
5. `hyphenated()` page text contains `"gradi-\nent descent"`. → test `PDFFixtureBuilderTests/hyphenatedLineEndsPreserved`
6. `slideBullets()` page bounds (`.mediaBox`) are 792×612 and the text contains `"• Supervised learning"` and `"2) Second step"`. → test `PDFFixtureBuilderTests/slideBulletsLandscape`
7. `withMetadata(title: "Linear Algebra Notes", author: "Ada Lovelace")` has `documentAttributes` title and author equal to those strings. → test `PDFFixtureBuilderTests/metadataTitleAuthor`
8. `encrypted()` opens with `isEncrypted == true` and `isLocked == true`; `unlock(withPassword: "wrong")` is false; `unlock(withPassword: "secret")` is true; then the text contains `"Encrypted fixture"`. → test `PDFFixtureBuilderTests/encryptedRequiresPassword`
9. `damaged()`: `PDFDocument(data:)` is nil or has `pageCount == 0`. → test `PDFFixtureBuilderTests/damagedDoesNotOpen`
10. `coloredRegion()` opens with 1 page and contains `"Figure 1: red box"`. → test `PDFFixtureBuilderTests/coloredRegionOpens`
11. `writeTemporary` writes a file that `PDFDocument(url:)` opens with the same page count. → test `PDFFixtureBuilderTests/writeTemporaryCreatesFile`

## Out of scope
- Any app (non-test) code. Text extraction, snapshot rendering, anchors (Phase 1/3, pdf-engine).
- Committed binary PDF files.

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 80/80, all fixture presets match spec, PDFKit font fallback not needed. Deviation: SymbolicTraits.monoSpace (SDK spelling).
