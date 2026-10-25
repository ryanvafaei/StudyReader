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
