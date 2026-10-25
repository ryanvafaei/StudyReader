import Foundation
import Testing
@testable import StudyReader

@Suite("CategoryManagerModel") @MainActor
struct CategoryManagerModelTests {
    private static let documentId = "60000000-0000-0000-0000-0000000000D1"

    @Test(.timeLimit(.minutes(1)))
    func deleteResetsDefaultCategory() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        let lab = try await env.categoryRepository.create(name: "Lab")
        try await env.documentRepository.insert(TestData.document(id: Self.documentId, categoryId: lab.id))
        session.settings.defaultCategoryId = lab.id

        let model = CategoryManagerModel(session: session)
        await model.delete(id: lab.id)

        #expect(model.errorMessage == nil)
        #expect(session.settings.defaultCategoryId == BuiltinCategory.lectureSlides.id)
        #expect(try await env.categoryRepository.fetch(id: lab.id) == nil)
        let document = try #require(try await env.documentRepository.fetch(id: Self.documentId))
        #expect(document.categoryId == BuiltinCategory.other.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteKeepsOtherDefaults() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        let lab = try await env.categoryRepository.create(name: "Lab")
        let thesis = try await env.categoryRepository.create(name: "Thesis")
        session.settings.defaultCategoryId = thesis.id

        let model = CategoryManagerModel(session: session)
        await model.delete(id: lab.id)

        #expect(model.errorMessage == nil)
        #expect(session.settings.defaultCategoryId == thesis.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func errorsAreShown() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        let model = CategoryManagerModel(session: session)

        await model.rename(id: BuiltinCategory.paper.id, to: "Essays")
        #expect(model.errorMessage == CategoryError.builtinCategory.errorDescription)
        #expect(try await env.categoryRepository.fetch(id: BuiltinCategory.paper.id)?.name == "Paper")

        model.dismissError()
        #expect(model.errorMessage == nil)

        await model.delete(id: BuiltinCategory.paper.id)
        #expect(model.errorMessage == CategoryError.builtinCategory.errorDescription)
        #expect(try await env.categoryRepository.fetch(id: BuiltinCategory.paper.id) != nil)
    }
}
