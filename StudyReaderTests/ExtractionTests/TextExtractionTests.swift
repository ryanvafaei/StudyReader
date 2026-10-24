import Foundation
import Testing
@testable import StudyReader

@Suite("TextExtraction")
struct TextExtractionTests {
    private func extract(_ data: Data, name: String = "fixture.pdf") throws -> [ExtractedPage] {
        let url = try PDFFixtureBuilder.writeTemporary(data, name: name)
        return try PDFTextExtractor.extract(fileAt: url)
    }

    private func substring(_ text: String, _ run: TextRun) -> String {
        (text as NSString).substring(with: NSRange(location: run.start, length: run.length))
    }

    @Test func joinsHyphenation() throws {
        let pages = try extract(PDFFixtureBuilder.hyphenated())
        #expect(pages.count == 1)
        #expect(pages[0].pageIndex == 0)
        #expect(pages[0].text == "The algorithm uses gradient descent to minimize the loss function.\n\nNext paragraph starts here.")
    }

    @Test func removesRepeatedHeaders() throws {
        let pages = try extract(PDFFixtureBuilder.repeatedHeaderFooter(pageCount: 6))
        #expect(pages.count == 6)
        for (index, page) in pages.enumerated() {
            let number = index + 1
            #expect(!page.text.contains(PDFFixtureBuilder.headerText))
            #expect(!page.text.contains("Introduction to Machine Learning"))
            for digit in 0...9 {
                #expect(!page.text.contains("Page \(digit)"))
            }
            #expect(page.text.contains("Body text on page \(number), line 1."))
            for line in 1...5 {
                #expect(page.text.contains("Body text on page \(number), line \(line)."))
            }
        }
    }

    @Test func joinsSoftHyphenAtLineEnd() {
        let result = PDFTextExtractor.process(rawPages: [
            "The photo\u{00AD}\nsynthesis rate",
            "Photo\u{00AD}\nSynthesis",
        ])
        #expect(result == ["The photosynthesis rate", "PhotoSynthesis"])
        #expect(PDFTextExtractor.process(rawPages: ["gradi\u{2010}\nent"]) == ["gradient"])
    }

    @Test func keepsBullets() throws {
        let pages = try extract(PDFFixtureBuilder.slideBullets())
        #expect(pages.count == 1)
        #expect(pages[0].text.contains(
            "• Supervised learning\n\n• Unsupervised learning\n\n• Clustering\n\n1. First step\n\n2) Second step"))
    }

    @Test func twoColumnIsDeterministic() throws {
        let data = PDFFixtureBuilder.twoColumn()
        let first = try extract(data, name: "first.pdf")
        let second = try extract(data, name: "second.pdf")
        #expect(first == second)
        #expect(first[0].text.contains("Left column line 1."))
        #expect(first[0].text.contains("Right column line 1."))
    }

    @Test func richRunsMarkBoldItalicMono() throws {
        let pages = try extract(PDFFixtureBuilder.richRuns())
        #expect(pages.count == 1)
        let page = pages[0]
        #expect(page.text == PDFFixtureBuilder.richRunsText)
        let bold = page.runs.filter { $0.bold }.map { substring(page.text, $0) }
        let italic = page.runs.filter { $0.italic }.map { substring(page.text, $0) }
        let mono = page.runs.filter { $0.mono }.map { substring(page.text, $0) }
        #expect(bold.contains("bold"))
        #expect(italic.contains("italic"))
        #expect(mono.contains("code"))
        #expect(page.runs.allSatisfy { $0.bold || $0.italic || $0.mono || $0.link != nil })
    }

    @Test func offsetsAndJoin() {
        let pages = [
            ExtractedPage(pageIndex: 0, text: "aaaaa", runs: []),
            ExtractedPage(pageIndex: 1, text: "", runs: []),
            ExtractedPage(pageIndex: 2, text: "bbb", runs: []),
        ]
        #expect(PDFTextExtractor.startOffsets(pages) == [0, 7, 9])
        #expect(PDFTextExtractor.joinedText(pages) == "aaaaa\n\n\n\nbbb")
    }

    @Test func lockedAndDamaged() throws {
        let locked = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.encrypted(), name: "locked.pdf")
        #expect(throws: PDFTextExtractionError.locked) { try PDFTextExtractor.extract(fileAt: locked) }
        let damaged = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.damaged(), name: "damaged.pdf")
        #expect(throws: PDFTextExtractionError.cannotOpen) { try PDFTextExtractor.extract(fileAt: damaged) }
    }

    @Test func searchSampleSoftHyphen() {
        let line = "x \(SearchSamples.photosynthesisSoftHyphen) y"
        let result = PDFTextExtractor.process(rawPages: [line])
        #expect(result == ["x photo\u{00AD}synthesis y"])
        #expect(result[0].contains("\u{00AD}"))
    }

    // MARK: Additional pipeline coverage

    @Test func versionIsOne() {
        #expect(PDFTextExtractor.version == 1)
    }

    @Test func normalizesLineEndingsSpacesAndBullets() {
        let result = PDFTextExtractor.process(rawPages: ["a\r\nb  \t c\r\n\r\n- dash\n3. num\n* star"])
        #expect(result == ["a b c\n\n• dash\n\n3. num\n\n• star"])
    }

    @Test func hyphenFollowedByCapitalIsNotJoined() {
        #expect(PDFTextExtractor.process(rawPages: ["well-\nKnown"]) == ["well-\n\nKnown"])
    }

    @Test func rawPipelineRemovesRepeatedHeadersAndPageNumbers() {
        let words = ["alpha", "beta", "gamma", "delta"]
        let pages = (1...4).map { number in
            "Course 101 - Week \(number)\nFirst \(words[number - 1]).\nMiddle line.\nFinal \(words[number - 1]).\nPage \(number) of 4"
        }
        let result = PDFTextExtractor.process(rawPages: pages)
        #expect(result == words.map { "First \($0).\n\nMiddle line.\n\nFinal \($0)." })
        #expect(PDFTextExtractor.process(rawPages: ["Hello.\n12\n3 / 9\nPAGE 7"]) == ["Hello."])
    }

    @Test func headerNeedsThreePages() {
        let pages = ["Lecture 1\nText one.", "Lecture 2\nText two."]
        #expect(PDFTextExtractor.process(rawPages: pages) == ["Lecture 1\n\nText one.", "Lecture 2\n\nText two."])
    }

    @Test func emptyPageGivesEmptyText() {
        #expect(PDFTextExtractor.process(rawPages: ["", "  \n\n "]) == ["", ""])
    }
}
