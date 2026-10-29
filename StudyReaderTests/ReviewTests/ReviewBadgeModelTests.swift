import Foundation
import GRDB
import Testing
@testable import StudyReader

@MainActor
@Suite("ReviewBadgeModel")
struct ReviewBadgeModelTests {
    @Test func countsTodaysPlan() async throws {
        // Four cards rated days before the session, so they are due at 05:00 on the reference day.
        let clock = FixedNow(ReviewTestFixture.base.addingTimeInterval(-10 * 86_400))
        let store = TestFileStore.make()
        try store.createRootDirectories()
        defer { TestFileStore.remove(store) }
        let settingsStore = TestSettings.make()
        defer { TestSettings.remove(settingsStore) }
        let env = AppEnvironment(
            fileStore: store,
            database: try AppDatabase.makeInMemory(),
            now: clock,
            settingsStore: settingsStore
        )
        let service = ReviewTestFixture.service(env, clock: clock)

        var dueCardIds: [String] = []
        for index in 0..<4 {
            let seeded = try await ReviewTestFixture.seedCard(env, text: "Due \(index)")
            dueCardIds.append(seeded.card.id)
            _ = try await service.rate(cardId: seeded.card.id, rating: .good, context: .daily)
        }
        // Seven cards that are never rated, so they stay new.
        for index in 0..<7 {
            _ = try await ReviewTestFixture.seedCard(env, text: "New \(index)")
        }

        clock.set(ReviewTestFixture.base.addingTimeInterval(5 * 3_600))
        let settings = AppSettings(store: settingsStore)
        settings.reviewNewPerDay = 5

        let badge = ReviewBadgeModel(environment: env, settings: settings, calendar: ReviewTestFixture.calendar)
        let observer = Task { await badge.observe() }
        defer { observer.cancel() }

        // 4 due, plus the 7 new cards capped at 5 by newPerDay.
        let nine = await TestWait.until { await badge.dailyDueCount == 9 }
        #expect(nine, "Badge should show 4 due plus 5 new (newPerDay caps the 7 new cards)")

        // Rating one due card removes it from the due count; the 5 new cards stay.
        let rated = try #require(dueCardIds.first)
        _ = try await service.rate(cardId: rated, rating: .good, context: .daily)

        let eight = await TestWait.until { await badge.dailyDueCount == 8 }
        #expect(eight, "Badge should drop to 8 after one due card is rated")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
