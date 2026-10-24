import AppKit
import Foundation
import Testing
@testable import StudyReader

@Suite struct MarkdownRendererTests {
    // MARK: Helpers

    private func render(_ markdown: String) -> RenderedMarkdown {
        MarkdownRenderer.render(MarkdownDocumentSource(markdown: markdown, documentId: nil, fileStore: nil))
    }

    private func range(of needle: String, in rendered: RenderedMarkdown) throws -> NSRange {
        let found = (rendered.string as NSString).range(of: needle)
        try #require(found.location != NSNotFound, "missing \(needle)")
        return found
    }

    private func font(of needle: String, in rendered: RenderedMarkdown) throws -> NSFont {
        let location = try range(of: needle, in: rendered).location
        return try #require(rendered.attributedString.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    private func attribute(
        _ key: NSAttributedString.Key,
        of needle: String,
        in rendered: RenderedMarkdown
    ) throws -> Any? {
        let location = try range(of: needle, in: rendered).location
        return rendered.attributedString.attribute(key, at: location, effectiveRange: nil)
    }

    private func attachments(in rendered: RenderedMarkdown) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []
        rendered.attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: rendered.attributedString.length)
        ) { value, _, _ in
            if let attachment = value as? NSTextAttachment { result.append(attachment) }
        }
        return result
    }

    private func redPixel(_ image: NSImage) throws -> Bool {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        try #require(drawn)
        return pixel[0] > 200 && pixel[1] < 50 && pixel[2] < 50 && pixel[3] == 255
    }

    private func makeStore() -> (store: FileStore, documentId: String, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownRendererTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return (FileStore(rootURL: root), UUID().uuidString, root)
    }

    private func copyImage(
        named source: String,
        from imagesFolder: URL,
        file: String,
        store: FileStore,
        documentId: String
    ) throws {
        let storedName = try #require(MarkdownImageNaming.storedFileName(forSource: source))
        let destination = try store.markdownImageURL(documentId: documentId, storedFileName: storedName)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: imagesFolder.appending(path: file), to: destination)
    }

    // MARK: Spec tests

    @Test func rendersAllElements() throws {
        let rendered = render(try MarkdownFixtures.string("all-elements"))
        let string = rendered.string

        for expected in [
            "Heading 1", "Heading 6", "emphasis", "strong text", "inline code", "Unordered item one",
            "Ordered item one", "Column A\tColumn B\tColumn C", "let answer = 42",
            "Final paragraph after the images.",
        ] {
            #expect(string.contains(expected), "missing \(expected)")
        }
        for unexpected in ["```", "**", "|", "- [ ]"] {
            #expect(!string.contains(unexpected), "unexpected \(unexpected)")
        }

        let h1 = try font(of: "Heading 1", in: rendered)
        let paragraph = try font(of: "A paragraph with", in: rendered)
        #expect(h1.pointSize > paragraph.pointSize)
        #expect(try font(of: "Heading 6", in: rendered).pointSize == paragraph.pointSize)
        #expect(try font(of: "Heading 2", in: rendered).pointSize < h1.pointSize)
        #expect(try font(of: "Heading 3", in: rendered).pointSize < (try font(of: "Heading 2", in: rendered)).pointSize)

        #expect(try font(of: "strong text", in: rendered).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!paragraph.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(try font(of: "emphasis", in: rendered).fontDescriptor.symbolicTraits.contains(.italic))
        #expect(try font(of: "inline code", in: rendered).fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(!paragraph.fontDescriptor.symbolicTraits.contains(.monoSpace))

        #expect(try attribute(.studyCodeBlock, of: "let answer", in: rendered) as? Bool == true)
        #expect(try font(of: "let answer", in: rendered).fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(try font(of: "let answer", in: rendered).pointSize < paragraph.pointSize)
        #expect(try attribute(.studyCodeBlock, of: "A paragraph with", in: rendered) == nil)
        #expect(try attribute(.studyBlockQuote, of: "A block quote", in: rendered) as? Bool == true)
        #expect(try attribute(.studyBlockQuote, of: "A paragraph with", in: rendered) == nil)

        let link = try attribute(.link, of: "link to Apple", in: rendered)
        #expect((link as? URL)?.absoluteString == "https://www.apple.com")
        #expect(try attribute(.link, of: "A paragraph with", in: rendered) == nil)
        let strike = try attribute(.strikethroughStyle, of: "strikethrough", in: rendered) as? Int
        #expect(strike == NSUnderlineStyle.single.rawValue)
        #expect(try attribute(.strikethroughStyle, of: "A paragraph with", in: rendered) == nil)

        // Remaining F-03 elements.
        #expect(string.contains("•\tUnordered item one"))
        #expect(string.contains("•\tUnordered item two"))
        #expect(string.contains("◦\tNested item"))
        #expect(string.contains("1.\tOrdered item one"))
        #expect(string.contains("2.\tOrdered item two"))
        #expect(string.contains("☐\tOpen task"))
        #expect(string.contains("☑\tDone task"))
        #expect(string.contains("a1\tb1\tc1"))
        #expect(string.contains("a2\tb2\tc2"))
        #expect(try font(of: "Column A", in: rendered).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!(try font(of: "a1", in: rendered)).fontDescriptor.symbolicTraits.contains(.bold))
        let tableStyle = try #require(try attribute(.paragraphStyle, of: "Column A", in: rendered) as? NSParagraphStyle)
        #expect(tableStyle.tabStops.map(\.location) == [140, 280])
        let rule = try attribute(.studyHorizontalRule, of: "\u{00A0}", in: rendered) as? Bool
        #expect(rule == true)
        #expect(!string.contains("\n\n"))
        #expect(string.first?.isWhitespace == false)
        #expect(string.last?.isWhitespace == false)
        #expect(!string.contains("# "))
        #expect(!string.contains("~~"))
    }

    @Test func imagesAndPlaceholders() throws {
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let sourceFolder = notes.deletingLastPathComponent()
        let (store, documentId, root) = makeStore()
        defer {
            try? FileManager.default.removeItem(at: sourceFolder)
            try? FileManager.default.removeItem(at: root)
        }
        try copyImage(
            named: "images/diagram.png",
            from: sourceFolder.appending(path: "images"),
            file: "diagram.png",
            store: store,
            documentId: documentId
        )

        let markdown = try String(contentsOf: notes, encoding: .utf8)
        let rendered = MarkdownRenderer.render(
            MarkdownDocumentSource(markdown: markdown, documentId: documentId, fileStore: store)
        )
        #expect(rendered.string.filter { $0 == "\u{FFFC}" }.count == 3)

        let found = attachments(in: rendered)
        #expect(found.count == 3)
        let first = try #require(found.first?.image)
        #expect(first.size == NSSize(width: 8, height: 8))
        #expect(found[0].bounds.size == CGSize(width: 8, height: 8))
        #expect(try redPixel(first))

        for placeholder in found.dropFirst() {
            let image = try #require(placeholder.image)
            #expect(image !== first)
            #expect(image.size.width > 0)
            #expect(placeholder.bounds.size == image.size)
        }
        #expect(found[1].image !== found[2].image)
    }

    @Test func hidesFrontMatter() throws {
        let rendered = render(try MarkdownFixtures.string("front-matter"))
        #expect(rendered.string.hasPrefix("Gradient Descent"))
        #expect(!rendered.string.contains("title:"))
        #expect(!rendered.string.contains("---"))
        #expect(rendered.frontMatter.title == "Gradient Descent Notes")
        #expect(rendered.frontMatter.author == "Ada Lovelace")
    }

    @Test func sourceMapForRichInline() throws {
        let rendered = render(try MarkdownFixtures.string("rich-inline"))
        #expect(rendered.string == "a bold and italic word with code")
        #expect(rendered.sourceMap.entries == [
            MarkdownSourceMap.Entry(range: NSRange(location: 2, length: 4), traits: .bold, linkDestination: nil),
            MarkdownSourceMap.Entry(range: NSRange(location: 11, length: 6), traits: .italic, linkDestination: nil),
            MarkdownSourceMap.Entry(range: NSRange(location: 28, length: 4), traits: .code, linkDestination: nil),
        ])
    }

    @Test func sectionsPartitionString() {
        let rendered = render("Intro\n\n# A\n\ntext\n\n## B\n\nmore\n\n### C\n\nx")
        #expect(rendered.string == "Intro\nA\ntext\nB\nmore\nC\nx")
        #expect(rendered.sections.count == 3)
        let nsString = rendered.string as NSString
        let texts = rendered.sections.map { nsString.substring(with: $0) }
        #expect(texts == ["Intro\n", "A\ntext\n", "B\nmore\nC\nx"])
        #expect(texts.joined() == rendered.string)
        #expect(rendered.sections.first?.location == 0)
        #expect(rendered.sections.last.map(NSMaxRange) == nsString.length)
        for (current, next) in zip(rendered.sections, rendered.sections.dropFirst()) {
            #expect(NSMaxRange(current) == next.location)
        }
    }

    @Test func deterministic() throws {
        let markdown = try MarkdownFixtures.string("all-elements")
        let source = MarkdownDocumentSource(markdown: markdown, documentId: nil, fileStore: nil)
        let first = MarkdownRenderer.render(source)
        let second = MarkdownRenderer.render(source)
        #expect(first.string == second.string)
        #expect(first.sourceMap == second.sourceMap)
        #expect(first.sections == second.sections)
    }

    @Test func rendersOffMainActor() async throws {
        let markdown = try MarkdownFixtures.string("all-elements")
        let source = MarkdownDocumentSource(markdown: markdown, documentId: nil, fileStore: nil)
        let string = await Task.detached { MarkdownRenderer.render(source).string }.value
        #expect(!string.isEmpty)
    }

    // MARK: Additional coverage

    @Test func versionIsOne() {
        #expect(MarkdownRenderer.version == 1)
    }

    @Test func sectionsWhenFirstBlockIsHeadingOrNoHeading() {
        let heading = render("# A\n\ntext\n\n# B\n\nmore")
        #expect(heading.sections.count == 2)
        #expect(heading.sections.first?.location == 0)
        #expect(render("just text").sections == [NSRange(location: 0, length: 9)])
        #expect(render("").sections.isEmpty)
        #expect(render("").string.isEmpty)
    }

    @Test func sourceMapForLinksNestingAndCodeBlocks() throws {
        let rendered = render("A [link **bold**](https://example.com) and ***both***.\n\n```\nx = 1\ny = 2\n```")
        let string = rendered.string as NSString
        let linkRange = string.range(of: "link bold")
        let boldRange = string.range(of: "bold", range: NSRange(location: linkRange.location + 5, length: 4))
        let bothRange = string.range(of: "both")
        let entries = rendered.sourceMap.entries
        #expect(entries.contains(.init(
            range: NSRange(location: linkRange.location, length: 5),
            traits: .link,
            linkDestination: "https://example.com"
        )))
        #expect(entries.contains(.init(range: boldRange, traits: [.link, .bold], linkDestination: "https://example.com")))
        #expect(entries.contains(.init(range: bothRange, traits: [.bold, .italic], linkDestination: nil)))
        let bothFont = try font(of: "both", in: rendered)
        #expect(bothFont.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(bothFont.fontDescriptor.symbolicTraits.contains(.italic))
        let codeLines = entries.filter { $0.traits == .code }
        #expect(codeLines.map { string.substring(with: $0.range) } == ["x = 1", "y = 2"])

        let sortedAndDisjoint = zip(entries, entries.dropFirst()).allSatisfy { NSMaxRange($0.range) <= $1.range.location }
        #expect(sortedAndDisjoint)
        #expect(entries.allSatisfy { NSMaxRange($0.range) <= string.length && $0.range.length > 0 })
    }

    @Test func imagesWithoutDocumentAreAllPlaceholders() throws {
        let rendered = render(try MarkdownFixtures.string("all-elements"))
        let found = attachments(in: rendered)
        #expect(found.count == 3)
        #expect(found.allSatisfy { $0.image != nil })
    }

    @Test func wideLocalImageIsScaledToMaxWidth() throws {
        let (store, documentId, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let storedName = try #require(MarkdownImageNaming.storedFileName(forSource: "big.png"))
        let url = try store.markdownImageURL(documentId: documentId, storedFileName: storedName)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)

        let rendered = MarkdownRenderer.render(
            MarkdownDocumentSource(markdown: "![wide](big.png)", documentId: documentId, fileStore: store)
        )
        let attachment = try #require(attachments(in: rendered).first)
        #expect(attachment.bounds.size == CGSize(width: 720, height: 360))
        #expect(attachment.image?.size == NSSize(width: 1000, height: 500))
    }

    @Test func blockStructure() {
        let rendered = render("""
        > quote one
        >
        > quote two

        - item

          continued

        <div>raw</div>

        Last
        """)
        #expect(rendered.string == "quote one\nquote two\n•\titem\ncontinued\n<div>raw</div>\nLast")
        let style = rendered.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.headIndent == 16)
        #expect(style?.lineHeightMultiple == 1.4)
        let itemLocation = (rendered.string as NSString).range(of: "•").location
        let itemStyle = rendered.attributedString.attribute(
            .paragraphStyle, at: itemLocation, effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(itemStyle?.headIndent == 20)
        #expect(itemStyle?.firstLineHeadIndent == 0)
        #expect(itemStyle?.tabStops.map(\.location) == [20])
    }

    @Test func baseFontSizeScalesFonts() throws {
        let source = MarkdownDocumentSource(markdown: "# H\n\nbody", documentId: nil, fileStore: nil)
        let rendered = MarkdownRenderer.render(source, style: MarkdownRenderStyle(baseFontSize: 20))
        #expect(try font(of: "body", in: rendered).pointSize == 20)
        #expect(try font(of: "H", in: rendered).pointSize == 40)
    }
}
