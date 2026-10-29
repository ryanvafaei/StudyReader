import Foundation

/// Which session a rating belongs to. `.themed` carries the themed review's id (ADR-0022).
enum ReviewSessionContext: Sendable, Equatable {
    case daily
    case themed(id: String)

    var sessionKind: ReviewSessionKind {
        switch self {
        case .daily: .daily
        case .themed: .themed
        }
    }

    var themedReviewId: String? {
        switch self {
        case .daily: nil
        case .themed(let id): id
        }
    }
}

/// The card after one rating and the review-log row it wrote.
struct RatingOutcome: Sendable, Equatable {
    var card: ReviewCard
    var log: ReviewLogEntry
}

enum ReviewServiceError: Error, Equatable, LocalizedError {
    case cardMissing
    case cardSuspended

    var errorDescription: String? {
        switch self {
        case .cardMissing: "This card no longer exists."
        case .cardSuspended: "This card is suspended."
        }
    }
}

/// The review actions the review UI models call (SPEC F-15, F-18; ADR-0021, ADR-0022). Owns the scheduler, the
/// clock and the calendar. Every time comes from `now()`, every write goes through the repositories.
actor ReviewService {
    private let cards: ReviewCardRepository
    private let highlights: HighlightRepository
    private let themedReviews: ThemedReviewRepository
    private let now: any Now
    private let calendar: Calendar
    private let scheduler: ReviewScheduler
    /// Supplies the seed of a themed session's random order (T122). Tests pass a fixed seed.
    private let makeSeed: @Sendable () -> UInt64

    init(
        cards: ReviewCardRepository,
        highlights: HighlightRepository,
        themedReviews: ThemedReviewRepository,
        now: any Now,
        calendar: Calendar = .current,
        scheduler: ReviewScheduler = ReviewScheduler(),
        makeSeed: @escaping @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) }
    ) {
        self.cards = cards
        self.highlights = highlights
        self.themedReviews = themedReviews
        self.now = now
        self.calendar = calendar
        self.scheduler = scheduler
        self.makeSeed = makeSeed
    }

    /// The daily queue for the review day that contains `now()`, planned with `limits` (DailyReviewBuilder).
    func dailyPlan(limits: DailyLimits) async throws -> DailyReviewPlan {
        let current = now()
        let snapshot = try await cards.dailyQueue(
            now: current,
            dayStart: ReviewDay.start(containing: current, calendar: calendar)
        )
        return DailyReviewBuilder.build(snapshot, limits: limits)
    }

    /// The themed plan (SPEC F-20, ADR-0022): the review's candidates for the review day that contains `now()`,
    /// picked by ThemedReviewBuilder with a fresh seed. A missing review throws `ThemedReviewError.notFound`.
    func themedPlan(reviewId: String) async throws -> (review: ThemedReview, cardIds: [String]) {
        guard let review = try await themedReviews.fetch(id: reviewId) else {
            throw ThemedReviewError.notFound
        }
        let current = now()
        let snapshot = try await themedReviews.themedQueue(
            filter: review.filter,
            dayStart: ReviewDay.start(containing: current, calendar: calendar)
        )
        let cardIds = ThemedReviewBuilder.build(snapshot, review: review, now: current, seed: makeSeed())
        return (review, cardIds)
    }

    /// Marks a themed review completed on the current review day (ADR-0022).
    func completeThemedReview(id: String) async throws {
        try await themedReviews.markCompleted(id: id, at: now())
    }

    func items(cardIds: [String]) async throws -> [ReviewCardItem] {
        try await cards.items(cardIds: cardIds)
    }

    func item(cardId: String) async throws -> ReviewCardItem? {
        try await cards.item(cardId: cardId)
    }

    /// Schedules one rating with FSRS and writes the card and its log in one transaction (ADR-0006, ADR-0021).
    /// The card is read fresh; a missing card throws `.cardMissing`, a suspended card or one with no retention
    /// (frequency Off) throws `.cardSuspended`. Nothing is written when either is thrown.
    func rate(cardId: String, rating: ReviewRating, context: ReviewSessionContext) async throws -> RatingOutcome {
        guard let item = try await cards.item(cardId: cardId) else {
            throw ReviewServiceError.cardMissing
        }
        guard !item.card.suspended,
              let retention = FrequencyPolicy.retention(
                  override: item.card.frequencyOverride,
                  category: item.categoryFrequency
              )
        else {
            throw ReviewServiceError.cardSuspended
        }

        let stored = try StoredFSRSCard(json: item.card.fsrsCard)
        let time = now()
        let scheduled = try scheduler.schedule(stored, rating: rating, now: time, retention: retention)
        let write = RatingWrite(
            cardId: cardId,
            fsrsCard: try scheduled.card.json(),
            dueAt: scheduled.card.due,
            state: scheduled.card.state,
            reviewedAt: time,
            rating: rating,
            sessionKind: context.sessionKind,
            themedReviewId: context.themedReviewId,
            fsrsLog: try scheduled.log.json()
        )
        let log: ReviewLogEntry
        do {
            log = try await cards.recordRating(write)
        } catch RepositoryError.notFound {
            throw ReviewServiceError.cardMissing
        }
        guard let card = try await cards.fetch(id: cardId) else {
            throw ReviewServiceError.cardMissing
        }
        return RatingOutcome(card: card, log: log)
    }

    /// SPEC F-18 "Change frequency". The new retention comes from the override (or the category when nil). For a
    /// reviewed card the due moves to `lastReview` plus the FSRS interval for that retention; a new card keeps its
    /// due. Off suspends the card (`.user`) through the repository.
    func setFrequencyOverride(cardId: String, _ override: ReviewFrequency?) async throws {
        guard let item = try await cards.item(cardId: cardId) else {
            throw ReviewServiceError.cardMissing
        }
        let retention = FrequencyPolicy.retention(override: override, category: item.categoryFrequency)

        var rescheduled: RescheduledCard?
        if let retention, item.card.state != .new {
            var stored = try StoredFSRSCard(json: item.card.fsrsCard)
            if let lastReview = stored.lastReview {
                let due = scheduler.rescheduledDue(stored, retention: retention)
                stored.due = due
                stored.scheduledDays = ((due.timeIntervalSince(lastReview)) / 86_400).rounded()
                rescheduled = RescheduledCard(fsrsCard: try stored.json(), dueAt: due)
            }
        }
        try await cards.updateFrequencyOverride(cardId: cardId, override: override, rescheduled: rescheduled)
    }

    /// SPEC F-18 "Edit highlight": stores `text` as the display text (nil or the original text clears the edit).
    func editHighlightText(highlightId: String, _ text: String?) async throws {
        try await highlights.updateEditedText(id: highlightId, editedText: text, at: now())
    }

    /// Cards due before the end of tomorrow's review day.
    func dueTomorrowCount() async throws -> Int {
        let tomorrow = ReviewDay.start(after: now(), calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow.addingTimeInterval(86_400)
        return try await cards.dueCount(before: end)
    }
}
