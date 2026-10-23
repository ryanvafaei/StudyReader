import CoreGraphics
import CoreText
import Foundation

enum FixtureFont: Sendable, CaseIterable {
    case regular, bold, italic, boldItalic, mono

    /// "Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique", "Menlo-Regular"
    var postScriptName: String {
        switch self {
        case .regular: "Helvetica"
        case .bold: "Helvetica-Bold"
        case .italic: "Helvetica-Oblique"
        case .boldItalic: "Helvetica-BoldOblique"
        case .mono: "Menlo-Regular"
        }
    }
}

struct FixtureRun: Sendable, Equatable {
    var text: String
    var font: FixtureFont = .regular

    init(_ text: String, font: FixtureFont = .regular) {
        self.text = text
        self.font = font
    }
}

enum FixtureElement: Sendable {
    /// One line of text. `origin` is the baseline start in PDF page space (points, origin bottom-left).
    case line([FixtureRun], origin: CGPoint, fontSize: CGFloat)
    /// Filled rectangle in page space, RGB 0...1.
    case filledRect(CGRect, red: CGFloat, green: CGFloat, blue: CGFloat)
}

struct FixturePage: Sendable {
    var elements: [FixtureElement]

    init(_ elements: [FixtureElement]) {
        self.elements = elements
    }
}

struct PDFFixtureOptions: Sendable {
    var pageSize: CGSize = CGSize(width: 612, height: 792)   // US Letter portrait
    var title: String? = nil
    var author: String? = nil
    var userPassword: String? = nil
    var ownerPassword: String? = nil

    init(pageSize: CGSize = CGSize(width: 612, height: 792), title: String? = nil, author: String? = nil,
         userPassword: String? = nil, ownerPassword: String? = nil) {
        self.pageSize = pageSize
        self.title = title
        self.author = author
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword
    }
}

enum PDFFixtureBuilder {
    // MARK: Core

    /// Draws each page into a CGContext(consumer:mediaBox:auxiliaryInfo:) PDF context backed by NSMutableData.
    static func makePDF(pages: [FixturePage], options: PDFFixtureOptions = PDFFixtureOptions()) -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            preconditionFailure("CGDataConsumer could not wrap NSMutableData")
        }

        var auxiliary: [String: Any] = [:]
        if let title = options.title {
            auxiliary[kCGPDFContextTitle as String] = title
        }
        if let author = options.author {
            auxiliary[kCGPDFContextAuthor as String] = author
        }
        if let userPassword = options.userPassword {
            auxiliary[kCGPDFContextUserPassword as String] = userPassword
            auxiliary[kCGPDFContextOwnerPassword as String] = options.ownerPassword ?? userPassword
        } else if let ownerPassword = options.ownerPassword {
            auxiliary[kCGPDFContextOwnerPassword as String] = ownerPassword
        }

        var mediaBox = CGRect(origin: .zero, size: options.pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, auxiliary as CFDictionary) else {
            preconditionFailure("CGContext could not be created for the PDF fixture")
        }

        for page in pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            for element in page.elements {
                draw(element, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Consecutive single-run lines, top to bottom: line i baseline at (x, topY - i * lineHeight).
    static func lines(_ texts: [String], font: FixtureFont = .regular, fontSize: CGFloat = 12,
                      x: CGFloat = 72, topY: CGFloat = 720, lineHeight: CGFloat = 16) -> [FixtureElement] {
        texts.enumerated().map { index, text in
            FixtureElement.line([FixtureRun(text, font: font)],
                                origin: CGPoint(x: x, y: topY - CGFloat(index) * lineHeight),
                                fontSize: fontSize)
        }
    }

    /// Writes data to FileManager.default.temporaryDirectory/PDFFixtures/<UUID>/<name> and returns the URL.
    static func writeTemporary(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PDFFixtures", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try data.write(to: url)
        return url
    }

    // MARK: Presets

    static func plainMultiPage(pageCount: Int = 5) -> Data {
        let pages = (0..<pageCount).map { index in
            let page = index + 1
            return FixturePage(lines((1...10).map { line in
                "Page \(page) line \(line): The quick brown fox jumps over the lazy dog."
            }))
        }
        return makePDF(pages: pages)
    }

    static func twoColumn() -> Data {
        let left = lines((1...12).map { "Left column line \($0)." }, fontSize: 11, x: 72)
        let right = lines((1...12).map { "Right column line \($0)." }, fontSize: 11, x: 330)
        return makePDF(pages: [FixturePage(left + right)])
    }

    static func repeatedHeaderFooter(pageCount: Int = 6) -> Data {
        let pages = (0..<pageCount).map { index in
            let page = index + 1
            var elements: [FixtureElement] = [
                text(headerText, at: CGPoint(x: 72, y: 750), size: 10)
            ]
            elements += lines((1...5).map { "Body text on page \(page), line \($0)." }, topY: 700)
            elements.append(text("Page \(page) of \(pageCount)", at: CGPoint(x: 72, y: 40), size: 10))
            return FixturePage(elements)
        }
        return makePDF(pages: pages)
    }

    static func richRuns() -> Data {
        let element = FixtureElement.line([
            FixtureRun("a "),
            FixtureRun("bold", font: .bold),
            FixtureRun(" and "),
            FixtureRun("italic", font: .italic),
            FixtureRun(" word with "),
            FixtureRun("code", font: .mono),
        ], origin: CGPoint(x: 72, y: 720), fontSize: 14)
        return makePDF(pages: [FixturePage([element])])
    }

    static func hyphenated() -> Data {
        makePDF(pages: [FixturePage(lines(hyphenatedLines))])
    }

    static func slideBullets() -> Data {
        var elements: [FixtureElement] = [
            text("Key Ideas", at: CGPoint(x: 60, y: 540), size: 28, font: .bold)
        ]
        elements += lines(slideBulletLines, fontSize: 20, x: 60, topY: 480, lineHeight: 32)
        return makePDF(pages: [FixturePage(elements)],
                       options: PDFFixtureOptions(pageSize: CGSize(width: 792, height: 612)))
    }

    static func coloredRegion() -> Data {
        makePDF(pages: [FixturePage([
            .filledRect(coloredRect, red: 1, green: 0, blue: 0),
            text("Figure 1: red box", at: CGPoint(x: 100, y: 80), size: 12),
        ])])
    }

    static func withMetadata(title: String, author: String) -> Data {
        makePDF(pages: [FixturePage(lines(["Metadata fixture"]))],
                options: PDFFixtureOptions(title: title, author: author))
    }

    static func encrypted(password: String = "secret") -> Data {
        makePDF(pages: [FixturePage(lines(["Encrypted fixture"]))],
                options: PDFFixtureOptions(userPassword: password, ownerPassword: password))
    }

    /// Truncated, not a valid PDF.
    static func damaged() -> Data {
        Data("%PDF-1.7\n%StudyReader damaged fixture\n1 0 obj\n<<".utf8)
    }

    // MARK: Helpers

    private static func text(_ string: String, at origin: CGPoint, size: CGFloat,
                             font: FixtureFont = .regular) -> FixtureElement {
        .line([FixtureRun(string, font: font)], origin: origin, fontSize: size)
    }

    private static func draw(_ element: FixtureElement, in context: CGContext) {
        switch element {
        case let .line(runs, origin, fontSize):
            drawLine(runs, origin: origin, fontSize: fontSize, in: context)
        case let .filledRect(rect, red, green, blue):
            context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            context.fill(rect)
        }
    }

    private static func drawLine(_ runs: [FixtureRun], origin: CGPoint, fontSize: CGFloat,
                                 in context: CGContext) {
        let attributed = NSMutableAttributedString()
        for run in runs {
            let font = CTFontCreateWithName(run.font.postScriptName as CFString, fontSize, nil)
            attributed.append(NSAttributedString(string: run.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]))
        }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        context.textPosition = origin
        CTLineDraw(line, context)
    }
}

extension PDFFixtureBuilder {
    static let headerText = "Introduction to Machine Learning — Lecture 3"
    static let richRunsText = "a bold and italic word with code"
    static let hyphenatedLines = ["The algorithm uses gradi-", "ent descent to minimize the",
                                  "loss function.", "Next paragraph starts here."]
    static let slideBulletLines = ["• Supervised learning", "• Unsupervised learning", "– Clustering",
                                   "1. First step", "2) Second step"]
    static let coloredRect = CGRect(x: 100, y: 100, width: 200, height: 150)
}
