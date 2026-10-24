import AppKit
import Foundation
import PDFKit

struct ExtractedPage: Sendable, Equatable {
    var pageIndex: Int
    /// ARCHITECTURE §6 output for this page; "" for pages without text.
    var text: String
    /// Offsets are UTF-16 within `text`. Only runs with bold, italic, mono or link set; adjacent runs with identical
    /// attributes are merged.
    var runs: [TextRun]
}

enum PDFTextExtractionError: Error, Equatable {
    case cannotOpen
    case locked
}

/// PDF text extraction for search and the text view (ARCHITECTURE §6, ADR-0009). Pure and deterministic: the same
/// input always yields the same text and runs, because text anchors store UTF-16 offsets into this output.
enum PDFTextExtractor {
    /// Bump when output text changes (ARCHITECTURE §6); stored in `document.extractionVersion`.
    static let version = 1

    /// Opens its own `PDFDocument(url:)`; no PDFKit object enters or leaves (ARCHITECTURE §3). Callable off the main
    /// actor.
    static func extract(fileAt url: URL) throws -> [ExtractedPage] {
        guard let document = PDFDocument(url: url) else { throw PDFTextExtractionError.cannotOpen }
        if document.isLocked { throw PDFTextExtractionError.locked }
        var sources: [[Cell]] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                sources.append([])
                continue
            }
            sources.append(cells(of: page))
        }
        return process(cellPages: sources).enumerated().map { index, result in
            ExtractedPage(pageIndex: index, text: result.text, runs: result.runs)
        }
    }

    /// The text-only pipeline (§6 steps 1-8) over raw page strings, for tests without PDFKit and for reuse.
    static func process(rawPages: [String]) -> [String] {
        let sources = rawPages.map { cells(of: NSAttributedString(string: $0)) }
        return process(cellPages: sources).map(\.text)
    }

    /// The joined text-view string: pages joined with "\n\n".
    static func joinedText(_ pages: [ExtractedPage]) -> String {
        pages.map(\.text).joined(separator: "\n\n")
    }

    /// UTF-16 start offset of each page in `joinedText` (page i = sum of previous page lengths + 2 * i).
    static func startOffsets(_ pages: [ExtractedPage]) -> [Int] {
        var offsets: [Int] = []
        var next = 0
        for page in pages {
            offsets.append(next)
            next += page.text.utf16.count + 2
        }
        return offsets
    }
}

// MARK: - Pipeline

private struct Style: Equatable {
    var bold = false
    var italic = false
    var mono = false
    var link: String?

    static let plain = Style()

    var isPlain: Bool { self == .plain }
}

/// One Unicode scalar of source text with the style it had in the PDF. Keeping the style per scalar through every
/// transformation is what lets runs map exactly onto the output text.
private struct Cell {
    var scalar: Unicode.Scalar
    var style: Style
}

private typealias Line = [Cell]

private let softHyphen: Unicode.Scalar = "\u{00AD}"
private let unicodeHyphen: Unicode.Scalar = "\u{2010}"
private let bulletSymbols: Set<Unicode.Scalar> = ["•", "▪", "◦", "–", "-", "*"]
private let sentenceEnders: Set<Unicode.Scalar> = [".", "?", "!", ":", ";"]

extension PDFTextExtractor {
    private static func cells(of page: PDFPage) -> [Cell] {
        if let attributed = page.attributedString, attributed.length > 0 {
            return cells(of: attributed)
        }
        if let string = page.string, !string.isEmpty {
            return cells(of: NSAttributedString(string: string))
        }
        return []
    }

    /// Step 1 (first half): NFC per attribute run, one cell per scalar.
    private static func cells(of attributed: NSAttributedString) -> [Cell] {
        var result: [Cell] = []
        let full = NSRange(location: 0, length: attributed.length)
        let string = attributed.string as NSString
        attributed.enumerateAttributes(in: full, options: []) { attributes, range, _ in
            let style = style(from: attributes)
            let piece = string.substring(with: range).precomposedStringWithCanonicalMapping
            for scalar in piece.unicodeScalars {
                result.append(Cell(scalar: scalar, style: style))
            }
        }
        return result
    }

    private static func style(from attributes: [NSAttributedString.Key: Any]) -> Style {
        var style = Style()
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            style.bold = traits.contains(.bold)
            style.italic = traits.contains(.italic)
            style.mono = traits.contains(.monoSpace) || font.isFixedPitch
        }
        if let url = attributes[.link] as? URL {
            style.link = url.absoluteString
        } else if let text = attributes[.link] as? String {
            style.link = text
        }
        return style
    }

    fileprivate static func process(cellPages: [[Cell]]) -> [(text: String, runs: [TextRun])] {
        let pageLines = cellPages.map { lines(from: normalized($0)) }
        let kept = removingHeadersAndFooters(pageLines)
        return kept.map { assemble(paragraphs: paragraphs(from: $0)) }
    }

    /// Step 1 (second half): line endings to "\n", runs of spaces/tabs collapsed to one space.
    private static func normalized(_ cells: [Cell]) -> [Cell] {
        var result: [Cell] = []
        result.reserveCapacity(cells.count)
        var index = 0
        while index < cells.count {
            let cell = cells[index]
            index += 1
            switch cell.scalar {
            case "\r":
                if index < cells.count, cells[index].scalar == "\n" { index += 1 }
                result.append(Cell(scalar: "\n", style: cell.style))
            case " ", "\t":
                if let last = result.last, last.scalar == " " { continue }
                result.append(Cell(scalar: " ", style: cell.style))
            default:
                result.append(cell)
            }
        }
        return result
    }

    /// Step 2: split by "\n", trim each line. Empty lines are kept; they are paragraph breaks.
    private static func lines(from cells: [Cell]) -> [Line] {
        var result: [Line] = []
        var current: Line = []
        for cell in cells {
            if cell.scalar == "\n" {
                result.append(trimmed(current))
                current = []
            } else {
                current.append(cell)
            }
        }
        result.append(trimmed(current))
        return result
    }

    private static func trimmed(_ line: Line) -> Line {
        guard let first = line.firstIndex(where: { !$0.scalar.properties.isWhitespace }),
              let last = line.lastIndex(where: { !$0.scalar.properties.isWhitespace }) else { return [] }
        return Array(line[first...last])
    }

    private static func text(of line: Line) -> String {
        String(String.UnicodeScalarView(line.map(\.scalar)))
    }

    // MARK: Headers and footers (step 4)

    /// Removes repeated headers/footers and lone page-number lines. A candidate is one of the first 2 or last 2
    /// non-empty lines of a page. Its digit-normalized form must appear as a candidate on at least 3 pages and on at
    /// least half of them. A form that occurs on a page more than once in total is body text that merely shares a
    /// pattern ("Body text on page 1, line 1."), not a header, and does not count.
    private static func removingHeadersAndFooters(_ pageLines: [[Line]]) -> [[Line]] {
        var candidateKeys: [[Int: String]] = []
        var pagesWithKey: [String: Int] = [:]
        for lines in pageLines {
            let nonEmpty = lines.indices.filter { !lines[$0].isEmpty }
            let keys = nonEmpty.map { digitNormalized(text(of: lines[$0])) }
            var occurrences: [String: Int] = [:]
            for key in keys { occurrences[key, default: 0] += 1 }
            var candidates: [Int: String] = [:]
            for (position, lineIndex) in nonEmpty.enumerated()
            where position < 2 || position >= nonEmpty.count - 2 {
                let key = keys[position]
                if occurrences[key] == 1 { candidates[lineIndex] = key }
            }
            for key in Set(candidates.values) { pagesWithKey[key, default: 0] += 1 }
            candidateKeys.append(candidates)
        }
        let pageCount = pageLines.count
        let repeated = Set(pagesWithKey.filter { $0.value >= 3 && $0.value * 2 >= pageCount }.keys)

        return pageLines.enumerated().map { pageIndex, lines in
            var result: [Line] = []
            for (lineIndex, line) in lines.enumerated() {
                if let key = candidateKeys[pageIndex][lineIndex], repeated.contains(key) { continue }
                if !line.isEmpty, isPageNumber(text(of: line)) { continue }
                result.append(line)
            }
            return result
        }
    }

    private static func digitNormalized(_ string: String) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.map { ("0"..."9").contains($0) ? "#" : $0 }))
    }

    private static func isDigits(_ string: some StringProtocol) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    /// `^\d+$`, `^Page \d+( of \d+)?$`, `^\d+ / \d+$`, case-insensitive.
    private static func isPageNumber(_ string: String) -> Bool {
        if isDigits(string) { return true }
        let lowered = string.lowercased()
        if lowered.hasPrefix("page ") {
            let parts = lowered.dropFirst(5).split(separator: " ", omittingEmptySubsequences: false)
            if parts.count == 1 { return isDigits(parts[0]) }
            if parts.count == 3 { return isDigits(parts[0]) && parts[1] == "of" && isDigits(parts[2]) }
            return false
        }
        let parts = lowered.split(separator: " ", omittingEmptySubsequences: false)
        return parts.count == 3 && isDigits(parts[0]) && parts[1] == "/" && isDigits(parts[2])
    }

    // MARK: Bullets and joining (steps 3, 5-7)

    private static func isBullet(_ line: Line) -> Bool {
        guard let first = line.first, line.count > 1 else { return false }
        if bulletSymbols.contains(first.scalar) { return line[1].scalar.properties.isWhitespace }
        var index = 0
        while index < line.count, ("0"..."9").contains(line[index].scalar) { index += 1 }
        guard index > 0, index + 1 < line.count else { return false }
        return (line[index].scalar == "." || line[index].scalar == ")") && line[index + 1].scalar.properties.isWhitespace
    }

    /// Symbol bullets become "• " + rest; numbered bullets are unchanged.
    private static func rewrittenBullet(_ line: Line) -> Line {
        guard bulletSymbols.contains(line[0].scalar) else { return line }
        var result = line
        result[0].scalar = "•"
        result[1].scalar = " "
        return result
    }

    private static func startsLowercase(_ line: Line) -> Bool {
        guard let first = line.first else { return false }
        return Character(first.scalar).isLowercase
    }

    private static func paragraphs(from lines: [Line]) -> [Line] {
        var paragraphs: [Line] = []
        var current: Line = []

        func flush() {
            if !current.isEmpty { paragraphs.append(current) }
            current = []
        }

        for line in lines {
            if line.isEmpty {
                flush()
            } else if isBullet(line) {
                flush()
                current = rewrittenBullet(line)
            } else if let last = current.last {
                if last.scalar == softHyphen {
                    current.removeLast()
                    current += line
                } else if (last.scalar == "-" || last.scalar == unicodeHyphen), startsLowercase(line) {
                    current.removeLast()
                    current += line
                } else if !sentenceEnders.contains(last.scalar), startsLowercase(line) {
                    let style = last.style == line[0].style ? last.style : Style.plain
                    current.append(Cell(scalar: " ", style: style))
                    current += line
                } else {
                    flush()
                    current = line
                }
            } else {
                current = line
            }
        }
        flush()
        return paragraphs
    }

    /// Steps 6 and 7: paragraphs joined with "\n\n", runs derived from the per-scalar styles.
    private static func assemble(paragraphs: [Line]) -> (text: String, runs: [TextRun]) {
        var all: [Cell] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                all.append(Cell(scalar: "\n", style: .plain))
                all.append(Cell(scalar: "\n", style: .plain))
            }
            all += paragraph
        }

        var runs: [TextRun] = []
        var offset = 0
        var runStart = 0
        var runStyle = Style.plain

        func closeRun(at end: Int) {
            guard !runStyle.isPlain, end > runStart else { return }
            runs.append(TextRun(start: runStart, length: end - runStart, bold: runStyle.bold,
                                italic: runStyle.italic, mono: runStyle.mono, link: runStyle.link))
        }

        for cell in all {
            if cell.style != runStyle {
                closeRun(at: offset)
                runStart = offset
                runStyle = cell.style
            }
            offset += cell.scalar.value > 0xFFFF ? 2 : 1
        }
        closeRun(at: offset)
        return (text(of: all), runs)
    }
}
