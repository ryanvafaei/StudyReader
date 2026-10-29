import Foundation
import Testing
@testable import StudyReader

@Suite("ReviewSettingsModel") @MainActor
struct ReviewSettingsModelTests {
    @Test(.timeLimit(.minutes(1)))
    func frequencyAndAutoCreateWrites() async throws {
        let db = try AppDatabase.makeInMemory()
        let repository = CategoryRepository(database: db)
        let model = ReviewSettingsModel(categories: repository)

        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        try await waitUntil { model.categories.count == 5 }

        await model.setFrequency(.off, for: BuiltinCategory.notes.id)
        await model.setAutoCreateCards(false, for: BuiltinCategory.paper.id)

        try await waitUntil {
            model.categories.first { $0.id == BuiltinCategory.notes.id }?.frequency == .off
                && model.categories.first { $0.id == BuiltinCategory.paper.id }?.autoCreateCards == false
        }
        #expect(model.errorMessage == nil)
        #expect(try await repository.fetch(id: BuiltinCategory.notes.id)?.frequency == .off)
        #expect(try await repository.fetch(id: BuiltinCategory.paper.id)?.autoCreateCards == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedWriteShowsMessage() async throws {
        let db = try AppDatabase.makeInMemory()
        let model = ReviewSettingsModel(categories: CategoryRepository(database: db))

        await model.setFrequency(.high, for: "missing-id")

        #expect(model.errorMessage != nil)
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
