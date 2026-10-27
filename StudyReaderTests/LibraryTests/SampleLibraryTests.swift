#if DEBUG
import Foundation
import ImageIO
import Testing
@testable import StudyReader

@Suite("SampleLibrary")
struct SampleLibraryTests {
    @Test("seeding is idempotent and removal deletes only the samples")
    func seedAndRemoveLeavesRealDocuments() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }

        let real = TestData.document(
            id: "6B1E0000-0000-4000-8000-0000000000AA",
            title: "Real document",
            author: "",
            categoryId: BuiltinCategory.other.id,
            fileType: .markdown,
            fileHash: "real-document",
            addedAt: TestData.referenceDate
        )
        try await env.documentRepository.insert(real)
        let sample = SampleLibrary(environment: env)

        #expect(try await sample.seed() == 7)
        #expect(try await sample.seed() == 0)
        #expect(try await env.documentRepository.fetchAll().count == 8)

        #expect(try await sample.removeSamples() == 7)
        #expect(try await sample.removeSamples() == 0)
        let remaining = try await env.documentRepository.fetchAll()
        #expect(remaining.map(\.id) == [real.id])
    }

    @Test("every seeded Markdown highlight resolves unchanged against what the reader renders")
    func seededMarkdownHighlightsMatchTheRenderedText() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        _ = try await SampleLibrary(environment: env).seed()

        var checked = 0
        for document in try await env.documentRepository.fetchAll() where document.fileType == .markdown {
            let url = try #require(env.fileStore.url(forRelativePath: document.storedPath))
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let rendered = MarkdownRenderer.render(
                MarkdownDocumentSource(markdown: markdown, documentId: document.id, fileStore: env.fileStore)
            ).string
            for highlight in try await env.highlightRepository.fetchForDocument(document.id) {
                guard case .text(let anchor) = highlight.anchor else {
                    Issue.record("A Markdown highlight has no text anchor: \(highlight.text)")
                    continue
                }
                #expect(
                    TextAnchoring.resolve(anchor, in: rendered, currentVersion: MarkdownRenderer.version) == .unchanged,
                    "\"\(highlight.text)\" doesn't sit at its stored offset of the rendered text."
                )
                #expect((rendered as NSString).substring(with: NSRange(location: anchor.start, length: anchor.length)) == highlight.text)
                #expect(highlight.anchorStatus == .ok)
                checked += 1
            }
        }
        #expect(checked >= 4)
    }

    @Test("the 16:9 slide-deck sample has a landscape cover no larger than the 600 px cap")
    func landscapeSampleHasLandscapeCover() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        _ = try await SampleLibrary(environment: env).seed()

        let slides = try #require(
            try await env.documentRepository.fetch(id: "5A4D0000-0000-4000-8000-000000000007")
        )
        let coverPath = try #require(slides.coverPath)
        let coverURL = try #require(env.fileStore.url(forRelativePath: coverPath))
        let source = try #require(CGImageSourceCreateWithURL(coverURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)

        #expect(width > height)
        #expect(max(width, height) <= CoverRenderer.maxPixelSize)
    }
}
#endif
