#if DEBUG
import Foundation
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

        #expect(try await sample.seed() == 6)
        #expect(try await sample.seed() == 0)
        #expect(try await env.documentRepository.fetchAll().count == 7)

        #expect(try await sample.removeSamples() == 6)
        #expect(try await sample.removeSamples() == 0)
        let remaining = try await env.documentRepository.fetchAll()
        #expect(remaining.map(\.id) == [real.id])
    }
}
#endif
