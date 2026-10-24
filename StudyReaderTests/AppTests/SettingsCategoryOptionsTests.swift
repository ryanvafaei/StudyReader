import Foundation
import Testing
@testable import StudyReader

@Suite("SettingsCategoryOptions") @MainActor
struct SettingsCategoryOptionsTests {
    private static let custom = DocumentCategory(
        id: "30000000-0000-0000-0000-0000000000c1",
        name: "Thesis reading",
        sortOrder: 10
    )

    private static func builtins() -> [DocumentCategory] {
        BuiltinCategory.allCases.map {
            DocumentCategory(id: $0.id, name: $0.name, isBuiltin: true, sortOrder: $0.sortOrder)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func liveListFollowsRepositoryOrderAndChanges() async throws {
        let db = try AppDatabase.makeInMemory()
        let repository = CategoryRepository(database: db)
        let options = SettingsCategoryOptions(repository: repository)

        let observing = Task { await options.observe() }
        defer { observing.cancel() }

        try await waitUntil { options.categories.count == 5 }
        #expect(options.categories.map(\.name) == ["Lecture slides", "Paper", "Book chapter", "Notes", "Other"])
        #expect(options.loadFailed == false)

        _ = try await repository.create(name: Self.custom.name)
        try await waitUntil { options.categories.count == 6 }
        #expect(options.categories.last?.name == "Thesis reading")
    }

    @Test func savedIdPresentIsKept() {
        let categories = Self.builtins()
        let saved = BuiltinCategory.notes.id

        #expect(SettingsCategoryOptions.effectiveSelection(saved: saved, in: categories) == saved)
    }

    @Test func savedIdPresentIsKeptEvenWhenNotFirst() {
        let categories = Self.builtins() + [Self.custom]
        let saved = Self.custom.id

        #expect(SettingsCategoryOptions.effectiveSelection(saved: saved, in: categories) == saved)
    }

    @Test func missingSavedIdFallsBackToFirstInListOrder() {
        let categories = Self.builtins()
        let missing = "99999999-0000-0000-0000-000000000000"

        #expect(
            SettingsCategoryOptions.effectiveSelection(saved: missing, in: categories)
                == BuiltinCategory.lectureSlides.id
        )
    }

    @Test func fallbackUsesFirstElementNotLowestId() {
        let first = DocumentCategory(id: "ffffffff-0000-0000-0000-000000000001", name: "First", sortOrder: 0)
        let second = DocumentCategory(id: "00000000-0000-0000-0000-000000000001", name: "Second", sortOrder: 1)

        #expect(
            SettingsCategoryOptions.effectiveSelection(saved: "missing", in: [first, second]) == first.id
        )
    }

    @Test func emptyListReturnsNilForSavedId() {
        #expect(SettingsCategoryOptions.effectiveSelection(saved: BuiltinCategory.paper.id, in: []) == nil)
    }

    @Test func emptyListReturnsNilForMissingId() {
        #expect(SettingsCategoryOptions.effectiveSelection(saved: "missing", in: []) == nil)
    }

    @Test func notLoadedOptionsHaveNoSelection() throws {
        let db = try AppDatabase.makeInMemory()
        let options = SettingsCategoryOptions(repository: CategoryRepository(database: db))

        #expect(options.categories.isEmpty)
        #expect(
            SettingsCategoryOptions.effectiveSelection(saved: BuiltinCategory.other.id, in: options.categories)
                == nil
        )
    }

    /// Polls the main actor until `condition` holds. Fails the test after about 5 seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition not met in time")
    }
}
