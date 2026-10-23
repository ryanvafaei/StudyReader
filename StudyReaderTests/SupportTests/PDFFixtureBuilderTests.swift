import AppKit
import PDFKit
import Testing

@Suite struct PDFFixtureBuilderTests {

    private func normalizedText(_ page: PDFPage?) -> String {
        (page?.string ?? "")
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
    }

    @Test func plainMultiPageHasPagesAndText() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.plainMultiPage()))
        #expect(document.pageCount == 5)
        let page3 = normalizedText(document.page(at: 2))
        #expect(page3.contains("Page 3 line 7: The quick brown fox"))
    }

    @Test func twoColumnContainsBothColumns() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.twoColumn()))
        #expect(document.pageCount == 1)
        let text = normalizedText(document.page(at: 0))
        #expect(text.contains("Left column line 12."))
        #expect(text.contains("Right column line 12."))
    }

    @Test func repeatedHeaderOnEveryPage() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.repeatedHeaderFooter()))
        #expect(document.pageCount == 6)
        for index in 0..<document.pageCount {
            let text = normalizedText(document.page(at: index))
            let pageNumber = index + 1
            #expect(text.contains(PDFFixtureBuilder.headerText), "page \(pageNumber) header")
            #expect(text.contains("Page \(pageNumber) of 6"), "page \(pageNumber) footer")
        }
    }

    @Test func richRunsKeepFontTraits() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.richRuns()))
        let page = try #require(document.page(at: 0))
        let attributed = try #require(page.attributedString)
        let nsString = attributed.string as NSString
        #expect(attributed.string.contains(PDFFixtureBuilder.richRunsText))

        func font(of word: String) throws -> NSFont {
            let range = nsString.range(of: word)
            try #require(range.location != NSNotFound, "\(word) not found in attributed string")
            let value = attributed.attribute(.font, at: range.location, effectiveRange: nil)
            return try #require(value as? NSFont, "no font over \(word)")
        }

        let bold = try font(of: "bold")
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold) || bold.fontName.contains("Bold"),
                "bold font was \(bold.fontName)")

        let italic = try font(of: "italic")
        #expect(italic.fontDescriptor.symbolicTraits.contains(.italic)
                || italic.fontName.contains("Oblique") || italic.fontName.contains("Italic"),
                "italic font was \(italic.fontName)")

        let code = try font(of: "code")
        #expect(code.fontDescriptor.symbolicTraits.contains(.monoSpace) || code.fontName.contains("Menlo"),
                "code font was \(code.fontName)")
    }

    @Test func hyphenatedLineEndsPreserved() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.hyphenated()))
        let text = normalizedText(document.page(at: 0))
        #expect(text.contains("gradi-\nent descent"))
    }

    @Test func slideBulletsLandscape() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.slideBullets()))
        let page = try #require(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.width == 792)
        #expect(bounds.height == 612)
        let text = normalizedText(page)
        #expect(text.contains("• Supervised learning"))
        #expect(text.contains("2) Second step"))
    }

    @Test func metadataTitleAuthor() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.withMetadata(
            title: "Linear Algebra Notes", author: "Ada Lovelace")))
        let attributes = try #require(document.documentAttributes)
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Linear Algebra Notes")
        #expect(attributes[PDFDocumentAttribute.authorAttribute] as? String == "Ada Lovelace")
    }

    @Test func encryptedRequiresPassword() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.encrypted()))
        #expect(document.isEncrypted)
        #expect(document.isLocked)
        #expect(document.unlock(withPassword: "wrong") == false)
        #expect(document.unlock(withPassword: "secret"))
        #expect(normalizedText(document.page(at: 0)).contains("Encrypted fixture"))
    }

    @Test func damagedDoesNotOpen() {
        let document = PDFDocument(data: PDFFixtureBuilder.damaged())
        #expect(document == nil || document?.pageCount == 0)
    }

    @Test func coloredRegionOpens() throws {
        let document = try #require(PDFDocument(data: PDFFixtureBuilder.coloredRegion()))
        #expect(document.pageCount == 1)
        #expect(normalizedText(document.page(at: 0)).contains("Figure 1: red box"))
    }

    @Test func writeTemporaryCreatesFile() throws {
        let data = PDFFixtureBuilder.plainMultiPage()
        let url = try PDFFixtureBuilder.writeTemporary(data, name: "plain.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let written = try #require(PDFDocument(url: url))
        let original = try #require(PDFDocument(data: data))
        #expect(written.pageCount == original.pageCount)
    }
}
