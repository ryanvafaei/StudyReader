import Testing
import Foundation
@testable import StudyReader

/// Stored JSON shapes and the card factory (T97, ADR-0021).
@Suite struct StoredFSRSCardTests {
    private let now = TestData.referenceDate

    // MARK: StoredFSRSCard

    @Test func jsonRoundTrip() throws {
        let card = StoredFSRSCard(
            due: Date(timeIntervalSince1970: 1_790_000_000.5),
            stability: 10.5,
            difficulty: 5.25,
            elapsedDays: 3,
            scheduledDays: 4,
            learningSteps: 1,
            reps: 2,
            lapses: 1,
            state: .relearning,
            lastReview: Date(timeIntervalSince1970: 1_789_000_000)
        )
        #expect(try StoredFSRSCard(json: card.json()) == card)

        let never = StoredFSRSCard.new(due: now)
        #expect(try StoredFSRSCard(json: never.json()) == never)
    }

    @Test func emptyJSONDecodesAsNewCard() throws {
        let card = try StoredFSRSCard(json: "{}")
        #expect(card.state == .new)
        #expect(card.stability == 0)
        #expect(card.difficulty == 0)
        #expect(card.elapsedDays == 0)
        #expect(card.scheduledDays == 0)
        #expect(card.learningSteps == 0)
        #expect(card.reps == 0)
        #expect(card.lapses == 0)
        #expect(card.lastReview == nil)
        #expect(card.due == Date(timeIntervalSince1970: 0))
    }

    @Test func jsonKeysAreStable() throws {
        let card = StoredFSRSCard(
            due: Date(timeIntervalSince1970: 1_790_000_000),
            stability: 10.5,
            difficulty: 5,
            reps: 2,
            state: .review,
            lastReview: Date(timeIntervalSince1970: 1_789_000_000)
        )
        #expect(try card.json() == #"{"difficulty":5,"due":1790000000,"elapsedDays":0,"lapses":0,"lastReview":1789000000,"learningSteps":0,"reps":2,"scheduledDays":0,"stability":10.5,"state":"review"}"#)
    }

    @Test func nilLastReviewIsOmitted() throws {
        let json = try StoredFSRSCard.new(due: now).json()
        #expect(!json.contains("lastReview"))
    }

    @Test func newCardIsStorageRounded() {
        let raw = Date(timeIntervalSince1970: 1_790_000_000.0004)
        #expect(StoredFSRSCard.new(due: raw).due == raw.storageRounded)
    }

    // MARK: StoredFSRSLog

    private var sampleLog: StoredFSRSLog {
        StoredFSRSLog(
            rating: .good,
            state: .review,
            due: Date(timeIntervalSince1970: 1_790_000_000),
            stability: 12.5,
            difficulty: 6,
            elapsedDays: 4,
            lastElapsedDays: 2,
            scheduledDays: 5,
            learningSteps: 0,
            review: Date(timeIntervalSince1970: 1_790_100_000)
        )
    }

    @Test func logJSONRoundTrip() throws {
        #expect(try StoredFSRSLog(json: sampleLog.json()) == sampleLog)
    }

    @Test func emptyJSONDecodesAsNewLog() throws {
        let log = try StoredFSRSLog(json: "{}")
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(log.rating == .again)
        #expect(log.state == .new)
        #expect(log.due == epoch)
        #expect(log.review == epoch)
        #expect(log.stability == 0)
        #expect(log.difficulty == 0)
        #expect(log.elapsedDays == 0)
        #expect(log.lastElapsedDays == 0)
        #expect(log.scheduledDays == 0)
        #expect(log.learningSteps == 0)
    }

    @Test func logJSONKeysAreStable() throws {
        #expect(try sampleLog.json() == #"{"difficulty":6,"due":1790000000,"elapsedDays":4,"lastElapsedDays":2,"learningSteps":0,"rating":3,"review":1790100000,"scheduledDays":5,"stability":12.5,"state":"review"}"#)
    }

    @Test func ratingRawValuesMatchFSRS() {
        #expect(ReviewRating.allCases.map(\.rawValue) == [1, 2, 3, 4])
    }

    // MARK: ReviewCardFactory

    @Test func factoryPassiveCard() throws {
        let card = try ReviewCardFactory.passive(highlightId: "h1", now: now)
        #expect(card.highlightId == "h1")
        #expect(card.cardType == .passive)
        #expect(card.state == .new)
        #expect(card.dueAt == now)
        #expect(card.createdAt == now)
        #expect(!card.suspended)
        #expect(card.suspendedReason == nil)
        #expect(card.introducedAt == nil)
        #expect(!card.id.isEmpty)
        #expect(try StoredFSRSCard(json: card.fsrsCard) == .new(due: now))

        let other = try ReviewCardFactory.passive(highlightId: "h1", now: now)
        #expect(other.id != card.id)
    }

    @Test(arguments: [CardType.cloze, CardType.qa])
    func factoryMasteryCard(cardType: CardType) throws {
        let card = try ReviewCardFactory.mastery(
            highlightId: "h2", cardType: cardType, clozeRanges: [[0, 4]],
            question: "Q?", answer: "A.", now: now
        )
        #expect(card.cardType == cardType)
        #expect(card.clozeRanges == [[0, 4]])
        #expect(card.question == "Q?")
        #expect(card.answer == "A.")
        #expect(card.state == .new)
        #expect(card.dueAt == now)
        #expect(card.createdAt == now)
        #expect(try StoredFSRSCard(json: card.fsrsCard) == .new(due: now))
    }

    @Test func factoryRejectsPassiveAsMastery() {
        #expect(throws: ReviewCardFactoryError.notMastery) {
            try ReviewCardFactory.mastery(
                highlightId: "h3", cardType: .passive, clozeRanges: nil, question: nil, answer: nil, now: now
            )
        }
    }
}
