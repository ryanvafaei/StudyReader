import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ReviewActions")
struct ReviewActionsTests {
    private let base = ReviewTestFixture.base

    @Test func frequencyChangeReschedulesFromLastReview() async throws {
        let time = base.addingTimeInterval(5 * 3_600)
        let clock = FixedNow(time)
        let env = try AppEnvironment.inMemory(now: clock)
        let (_, card) = try await ReviewTestFixture.seedCard(env)
        let service = ReviewTestFixture.service(env, clock: clock)
        _ = try await service.rate(cardId: card.id, rating: .good, context: .daily)

        let rated = try #require(try await env.reviewCardRepository.fetch(id: card.id))
        let stored = try StoredFSRSCard(json: rated.fsrsCard)
        let scheduler = ReviewScheduler(enableFuzz: false)

        let cases: [(override: ReviewFrequency?, retention: Double)] = [
            (.high, 0.95),
            (.low, 0.80),
            (nil, 0.90),
        ]
        var dueByRetention: [Double: Date] = [:]
        for testCase in cases {
            try await service.setFrequencyOverride(cardId: card.id, testCase.override)
            let updated = try #require(try await env.reviewCardRepository.fetch(id: card.id))
            let expected = scheduler.rescheduledDue(stored, retention: testCase.retention).storageRounded
            #expect(updated.dueAt == expected)
            #expect(updated.suspended == false)
            dueByRetention[testCase.retention] = updated.dueAt
        }

        let high = try #require(dueByRetention[0.95])
        let normal = try #require(dueByRetention[0.90])
        let low = try #require(dueByRetention[0.80])
        #expect(high < normal)
        #expect(normal < low)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func frequencyOffSuspendsAndLeavesThePlan() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (_, card) = try await ReviewTestFixture.seedCard(env)
        let service = ReviewTestFixture.service(env, clock: clock)

        try await service.setFrequencyOverride(cardId: card.id, .off)
        let suspended = try #require(try await env.reviewCardRepository.fetch(id: card.id))
        #expect(suspended.suspended == true)
        #expect(suspended.suspendedReason == .user)
        let offPlan = try await service.dailyPlan(limits: .defaults)
        #expect(offPlan.isEmpty)

        try await service.setFrequencyOverride(cardId: card.id, .normal)
        let restored = try #require(try await env.reviewCardRepository.fetch(id: card.id))
        #expect(restored.suspended == false)
        #expect(restored.suspendedReason == nil)
        let plan = try await service.dailyPlan(limits: .defaults)
        #expect(plan.cardIds.contains(card.id))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func newCardFrequencyChangeKeepsDue() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (_, card) = try await ReviewTestFixture.seedCard(env)
        let service = ReviewTestFixture.service(env, clock: clock)
        let before = try #require(try await env.reviewCardRepository.fetch(id: card.id))

        try await service.setFrequencyOverride(cardId: card.id, .high)

        let after = try #require(try await env.reviewCardRepository.fetch(id: card.id))
        #expect(after.state == .new)
        #expect(after.dueAt == before.dueAt)
        #expect(after.fsrsCard == before.fsrsCard)
        #expect(after.frequencyOverride == .high)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func editHighlightTextKeepsOriginal() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, _) = try await ReviewTestFixture.seedCard(env)
        let service = ReviewTestFixture.service(env, clock: clock)

        try await service.editHighlightText(highlightId: highlight.id, "Edited wording")
        let edited = try #require(try await env.highlightRepository.fetch(id: highlight.id))
        #expect(edited.editedText == "Edited wording")
        #expect(edited.text == highlight.text)

        try await service.editHighlightText(highlightId: highlight.id, "")
        let cleared = try #require(try await env.highlightRepository.fetch(id: highlight.id))
        #expect(cleared.editedText == nil)
        #expect(cleared.text == highlight.text)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test @MainActor func noteEditPersists() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, _) = try await ReviewTestFixture.seedCard(env)

        let model = NoteEditorModel(target: .highlight(highlight.id), environment: env)
        await model.load()
        model.text = "Remember the exam date"
        await model.flush()

        let stored = try #require(try await env.highlightRepository.fetch(id: highlight.id))
        #expect(stored.note == "Remember the exam date")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
