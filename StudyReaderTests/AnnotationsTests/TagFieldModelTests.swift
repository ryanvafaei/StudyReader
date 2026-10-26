import Foundation
import Testing
@testable import StudyReader

@Suite("TagFieldModel")
struct TagFieldModelTests {
    private static let documentId = "40000000-0000-0000-0000-0000000000D1"

    private static func tag(_ name: String, id: String = UUID().uuidString) -> LibraryTag {
        LibraryTag(id: id, name: name, createdAt: TestData.referenceDate)
    }

    @Test(.timeLimit(.minutes(1)))
    func suggestionsMatchPrefix() {
        let tags = [
            Self.tag("Biology", id: "t1"),
            Self.tag("bio-chem", id: "t2"),
            Self.tag("Exam", id: "t3"),
            Self.tag("Biopsy", id: "t4")
        ]

        // Case-insensitive prefix, with a leading "#" and surrounding spaces ignored.
        let bio = TagFieldModel.suggestions(for: "  #BIO ", in: tags, excluding: [])
        #expect(bio.map(\.id) == ["t1", "t2", "t4"])

        // Assigned tags are never suggested again.
        let excluded = TagFieldModel.suggestions(for: "bio", in: tags, excluding: ["t1"])
        #expect(excluded.map(\.id) == ["t2", "t4"])

        // A substring that is not a prefix does not match, and an empty query suggests nothing.
        #expect(TagFieldModel.suggestions(for: "ology", in: tags, excluding: []).isEmpty)
        #expect(TagFieldModel.suggestions(for: "   ", in: tags, excluding: []).isEmpty)

        // The limit caps the list and keeps the given order.
        let many = (0..<12).map { Self.tag("tag\($0)", id: "m\($0)") }
        let limited = TagFieldModel.suggestions(for: "tag", in: many, excluding: [], limit: 8)
        #expect(limited.count == 8)
        #expect(limited.first?.id == "m0")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func addCreatesOrReuses() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let model = TagFieldModel(target: .document(Self.documentId), environment: env)

        // A new name creates the tag and assigns it; the query clears.
        model.query = "Exam"
        await model.submit()
        #expect(model.errorMessage == nil)
        #expect(model.query.isEmpty)

        // The same name in another case reuses the tag and does not assign it twice.
        model.query = "exam"
        await model.submit()
        model.query = "#EXAM"
        await model.add(name: "#EXAM")

        let assigned = try await env.tagRepository.tags(forDocument: Self.documentId)
        #expect(assigned.map(\.name) == ["Exam"])
        let allTags = try await env.tagRepository.fetchAll()
        #expect(allTags.count == 1)

        // A blank query adds nothing.
        model.query = "   "
        await model.submit()
        let stillOne = try await env.tagRepository.tags(forDocument: Self.documentId)
        #expect(stillOne.count == 1)

        // An invalid name keeps the query and reports the error.
        model.query = String(repeating: "x", count: 41)
        await model.submit()
        #expect(model.errorMessage != nil)
        #expect(model.query.count == 41)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func documentTarget() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let model = TagFieldModel(target: .document(Self.documentId), environment: env)

        await model.add(name: "Biology")
        await model.add(name: "Chemistry")
        let assigned = try await env.tagRepository.tags(forDocument: Self.documentId)
        #expect(assigned.map(\.name) == ["Biology", "Chemistry"])

        let biologyId = try #require(assigned.first?.id)
        await model.remove(tagId: biologyId)
        let remaining = try await env.tagRepository.tags(forDocument: Self.documentId)
        #expect(remaining.map(\.name) == ["Chemistry"])
        // Removing from the document keeps the tag in the library.
        #expect(try await env.tagRepository.fetchAll().count == 2)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func returnAddsHighlightedSuggestionAfterSameValueWrite() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        _ = try await env.tagRepository.findOrCreate(name: "Sample · exam", at: TestData.referenceDate)
        _ = try await env.tagRepository.findOrCreate(name: "Sample · midterm", at: TestData.referenceDate)
        let model = TagFieldModel(target: .document(Self.documentId), environment: env)
        let observer = Task { await model.observe() }
        defer { observer.cancel() }

        model.query = "Sa"
        let ready = await ReaderTestSupport.waitUntil { model.suggestions.count == 2 }
        #expect(ready)

        // Arrow down highlights the first suggestion; the field then writes the same query back.
        model.moveHighlight(by: 1)
        model.query = "Sa"
        #expect(model.highlightedSuggestion == 0)

        let expected = try #require(model.suggestions.first)
        await model.submit()

        let assigned = try await env.tagRepository.tags(forDocument: Self.documentId)
        #expect(assigned.map(\.id).contains(expected.id))
        let allTags = try await env.tagRepository.fetchAll()
        #expect(!allTags.contains { $0.name == "Sa" })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func highlightSurvivesTagListRefresh() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        _ = try await env.tagRepository.findOrCreate(name: "Sample · exam", at: TestData.referenceDate)
        _ = try await env.tagRepository.findOrCreate(name: "Sample · midterm", at: TestData.referenceDate)
        let model = TagFieldModel(target: .document(Self.documentId), environment: env)
        let observer = Task { await model.observe() }
        defer { observer.cancel() }

        model.query = "Sa"
        let ready = await ReaderTestSupport.waitUntil { model.suggestions.count == 2 }
        #expect(ready)
        model.moveHighlight(by: 1)
        let index = try #require(model.highlightedSuggestion)
        let highlightedId = model.suggestions[index].id

        // An unrelated tag that also matches "Sa" makes observeAll() emit again. suggestions grows to 3
        // only when that emission has been applied, so the wait is a precise signal, not a timed guess.
        _ = try await env.tagRepository.findOrCreate(name: "Sample · zeta", at: TestData.referenceDate)
        let refreshed = await ReaderTestSupport.waitUntil { model.suggestions.count == 3 }
        #expect(refreshed)

        let current = try #require(model.highlightedSuggestion)
        #expect(model.suggestions.indices.contains(current) && model.suggestions[current].id == highlightedId)
    }
}
