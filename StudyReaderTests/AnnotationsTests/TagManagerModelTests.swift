import Foundation
import Testing
@testable import StudyReader

@Suite("TagManagerModel")
struct TagManagerModelTests {
    private static let documentId = "50000000-0000-0000-0000-0000000000D1"
    private static let highlightId = "50000000-0000-0000-0000-0000000000A1"

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func renameDuplicateShowsError() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        let model = TagManagerModel(environment: env)
        let exam = try await env.tagRepository.findOrCreate(name: "Exam", at: TestData.referenceDate)
        _ = try await env.tagRepository.findOrCreate(name: "Quiz", at: TestData.referenceDate)

        await model.rename(tagId: exam.id, to: "quiz")
        #expect(model.errorMessage == "A tag with this name already exists.")

        // A successful rename clears the error and the new name is stored.
        await model.rename(tagId: exam.id, to: "Midterm")
        #expect(model.errorMessage == nil)
        let names = try await env.tagRepository.fetchAll().map(\.name)
        #expect(names == ["Midterm", "Quiz"])

        // An invalid name reports a message too; dismissError clears it.
        await model.rename(tagId: exam.id, to: "   ")
        #expect(model.errorMessage != nil)
        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func mergeAndDelete() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        try await env.highlightRepository.insert(
            TestData.highlight(documentId: Self.documentId, id: Self.highlightId, positionKey: 10)
        )
        let repo = env.tagRepository
        let t0 = TestData.referenceDate
        let midterm = try await repo.findOrCreate(name: "midterm", at: t0)
        let midTerm = try await repo.findOrCreate(name: "mid-term", at: t0)
        let spare = try await repo.findOrCreate(name: "Spare", at: t0)
        try await repo.setTags([midTerm.id], forHighlight: Self.highlightId)
        try await repo.setTags([midterm.id], forDocument: Self.documentId)
        let model = TagManagerModel(environment: env)

        // Merge: the highlight and the document move to the target, and the source is gone.
        await model.merge(sourceId: midTerm.id, into: midterm.id)
        #expect(model.errorMessage == nil)
        let highlightTags = try await repo.tags(forHighlight: Self.highlightId)
        #expect(highlightTags.map(\.id) == [midterm.id])
        let documentTags = try await repo.tags(forDocument: Self.documentId)
        #expect(documentTags.map(\.id) == [midterm.id])
        let afterMerge = try await repo.fetchAll().map(\.id)
        #expect(afterMerge.contains(midTerm.id) == false)

        // Delete: only the tag and its links go; the highlight and document stay.
        await model.delete(tagId: spare.id)
        #expect(model.errorMessage == nil)
        #expect(try await repo.fetchAll().map(\.id) == [midterm.id])
        #expect(try await env.highlightRepository.fetch(id: Self.highlightId) != nil)
        #expect(try await env.documentRepository.fetch(id: Self.documentId) != nil)
    }
}
