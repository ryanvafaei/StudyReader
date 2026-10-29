import Foundation
import Observation

/// One rating button on the review screen (SPEC F-15, ADR-0022). Two buttons: Forgot ("1", .again) and Remembered
/// ("2", .good). Four buttons (Settings > Review): Again 1, Hard 2, Good 3, Easy 4.
struct RatingButton: Sendable, Equatable, Identifiable {
    var rating: ReviewRating
    var title: String
    var key: Character

    var id: Int { rating.rawValue }

    static func buttons(fourButtons: Bool) -> [RatingButton] {
        if fourButtons {
            return [
                RatingButton(rating: .again, title: String(localized: "Again"), key: "1"),
                RatingButton(rating: .hard, title: String(localized: "Hard"), key: "2"),
                RatingButton(rating: .good, title: String(localized: "Good"), key: "3"),
                RatingButton(rating: .easy, title: String(localized: "Easy"), key: "4"),
            ]
        }
        return [
            RatingButton(rating: .again, title: String(localized: "Forgot"), key: "1"),
            RatingButton(rating: .good, title: String(localized: "Remembered"), key: "2"),
        ]
    }
}

/// What a key press does on the review screen. `ReviewSessionModel.action(forKey:)` maps keys to these (ADR-0022).
enum ReviewKeyAction: Sendable, Equatable {
    case reveal
    case rate(ReviewRating)
}

/// The end-of-session numbers (SPEC F-15 summary).
struct ReviewSummary: Sendable, Equatable {
    var reviewed: Int
    /// Ratings other than `.again`.
    var remembered: Int
    /// Int((100 * remembered / reviewed).rounded()), 0 when reviewed is 0.
    var rememberedPercent: Int
    /// Cards due before the end of tomorrow's review day.
    var dueTomorrow: Int
}

/// The logic behind the review screen (SPEC F-15, F-18; ADR-0022). The session lives in memory: nothing is kept
/// between launches except what the rating writes. Views call these methods and read the state; they hold no logic.
@MainActor @Observable
final class ReviewSessionModel {
    enum Phase: Equatable {
        case idle                                    // nothing loaded
        case ready(dueCount: Int, newCount: Int)     // plan loaded, not started; (0, 0) = nothing to review
        case reviewing
        case finished(ReviewSummary)
        case failed(String)                          // user-facing message
    }

    private let environment: AppEnvironment
    private let settings: AppSettings
    private let context: ReviewSessionContext
    private var plan: DailyReviewPlan?
    private var reviewedCount = 0
    private var rememberedCount = 0

    private(set) var phase: Phase = .idle
    /// queue.first is the current card.
    private(set) var queue: [ReviewCardItem] = []
    private(set) var isRevealed = false
    /// A rating or action is being written.
    private(set) var isBusy = false
    /// Cards rated so far this session.
    private(set) var position: Int = 0
    /// Reset to false on every card change.
    var showOriginal = false
    /// The last action error, cleared by the next success.
    private(set) var errorMessage: String?
    /// The name of the themed review being run (nil in a daily session).
    private(set) var themedReviewName: String?

    init(session: AppSession, context: ReviewSessionContext = .daily) {
        self.environment = session.environment
        self.settings = session.settings
        self.context = context
    }

    var current: ReviewCardItem? {
        phase == .reviewing ? queue.first : nil
    }

    var content: ReviewCardContent? {
        current.map { ReviewCardContent.make($0, showOriginal: showOriginal) }
    }

    var ratingButtons: [RatingButton] {
        RatingButton.buttons(fourButtons: settings.showFourRatingButtons)
    }

    /// Reviewing, a current card, nothing being written, and revealed (or no reveal needed).
    var canRate: Bool {
        guard !isBusy, let content else { return false }
        return phase == .reviewing && (isRevealed || !content.needsReveal)
    }

    /// "\(position + 1) of \(position + queue.count)". A dropped card lowers the total; a skip changes nothing.
    var progressText: String {
        String(localized: "\(position + 1) of \(position + queue.count)")
    }

    /// Reviewing with a current card and nothing being written. Guards the card actions.
    private var canAct: Bool {
        phase == .reviewing && current != nil && !isBusy
    }

    /// Loads today's plan from the service (daily context), or the plan of the themed review (themed context).
    /// Does nothing while a session is running.
    func loadPlan() async {
        guard phase != .reviewing else { return }
        if case .themed(let reviewId) = context {
            await loadThemedPlan(reviewId: reviewId)
            return
        }
        do {
            let loaded = try await environment.reviewService.dailyPlan(limits: settings.dailyLimits)
            plan = loaded
            phase = .ready(dueCount: loaded.dueCount, newCount: loaded.newCount)
        } catch {
            Log.app.error("Review plan failed to load: \(String(describing: error), privacy: .public)")
            phase = .failed("The review plan couldn't be loaded.")
        }
    }

    /// Reads the cards of the loaded plan, in plan order. An empty plan finishes at once with a zero summary.
    func start() async {
        guard case .ready = phase, let plan else { return }
        do {
            let items = try await environment.reviewService.items(cardIds: plan.cardIds)
            queue = items
            self.plan = nil
            resetCounters()
            if items.isEmpty {
                phase = .finished(await makeSummary())
            } else {
                phase = .reviewing
            }
        } catch {
            Log.app.error("Review session failed to start: \(String(describing: error), privacy: .public)")
            phase = .failed("The review couldn't be started.")
        }
    }

    func reveal() {
        guard phase == .reviewing, content?.needsReveal == true else { return }
        isRevealed = true
    }

    /// Schedules the current card with `rating` (SPEC F-15). Missing or suspended cards are dropped without counting.
    func rate(_ rating: ReviewRating) async {
        guard canRate, let item = current else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await environment.reviewService.rate(cardId: item.card.id, rating: rating, context: context)
            errorMessage = nil
            reviewedCount += 1
            if rating != .again {
                rememberedCount += 1
            }
            dropFirst()
            position += 1
        } catch ReviewServiceError.cardMissing, ReviewServiceError.cardSuspended {
            errorMessage = nil
            dropFirst()
            // Dropped without a rating: the queue can empty here, but that does not complete a themed review.
            await finishIfEmpty(completingThemed: false)
            return
        } catch {
            Log.app.error("Rating failed: \(String(describing: error), privacy: .public)")
            errorMessage = "The rating couldn't be saved."
            return
        }
        // The queue emptied through a rating: a themed review completes here (ADR-0022).
        await finishIfEmpty(completingThemed: true)
    }

    /// SPEC F-18 Skip: the current card moves to the end. Nothing is written. A one-card queue stays as it is.
    func skip() {
        guard canAct, queue.count > 1 else { return }
        let first = queue.removeFirst()
        queue.append(first)
        isRevealed = false
        showOriginal = false
    }

    /// Synchronous so the view's `.onKeyPress` can answer at once (ADR-0022). " " reveals an unrevealed card that
    /// needs it; "1"…"4" rate through the button with that key when `canRate`; anything else is nil.
    func action(forKey key: Character) -> ReviewKeyAction? {
        if key == " " {
            guard content?.needsReveal == true, !isRevealed else { return nil }
            return .reveal
        }
        guard canRate, let button = ratingButtons.first(where: { $0.key == key }) else { return nil }
        return .rate(button.rating)
    }

    func perform(_ action: ReviewKeyAction) async {
        switch action {
        case .reveal:
            reveal()
        case .rate(let rating):
            await rate(rating)
        }
    }

    /// SPEC F-18 "Change frequency" for the current card. Off suspends it, so it leaves the queue.
    func setFrequency(_ override: ReviewFrequency?) async {
        guard canAct, let cardId = current?.card.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.reviewService.setFrequencyOverride(cardId: cardId, override)
            let fresh = try await environment.reviewService.item(cardId: cardId)
            errorMessage = nil
            replaceFirst(with: fresh, cardId: cardId, dropSuspended: true)
        } catch ReviewServiceError.cardMissing {
            errorMessage = nil
            replaceFirst(with: nil, cardId: cardId, dropSuspended: true)
        } catch {
            Log.app.error("Frequency change failed: \(String(describing: error), privacy: .public)")
            errorMessage = "The frequency couldn't be changed."
            return
        }
        await finishIfEmpty()
    }

    /// SPEC F-18 "Edit highlight" for the current card's highlight, then re-reads the card.
    func editHighlightText(_ text: String?) async {
        guard canAct, let highlightId = current?.highlight.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.reviewService.editHighlightText(highlightId: highlightId, text)
        } catch {
            Log.app.error("Highlight edit failed: \(String(describing: error), privacy: .public)")
            errorMessage = "The highlight couldn't be changed."
            return
        }
        errorMessage = nil
        await reloadCurrent()
    }

    /// Re-reads the current card (after a note edit or Open in Document). A card that no longer exists is dropped.
    func reloadCurrent() async {
        guard phase == .reviewing, let cardId = queue.first?.id else { return }
        do {
            let fresh = try await environment.reviewService.item(cardId: cardId)
            replaceFirst(with: fresh, cardId: cardId, dropSuspended: false)
        } catch {
            Log.app.error("Card reload failed: \(String(describing: error), privacy: .public)")
            return
        }
        await finishIfEmpty()
    }

    /// Back to idle. The view calls `loadPlan()` again to start over. Never completes a themed review (ADR-0022).
    func endSession() {
        phase = .idle
        queue = []
        plan = nil
        themedReviewName = nil
        resetCounters()
    }

    // MARK: - Helpers

    private func resetCounters() {
        reviewedCount = 0
        rememberedCount = 0
        position = 0
        isRevealed = false
        showOriginal = false
        errorMessage = nil
    }

    /// Removes the first card and resets the per-card state.
    private func dropFirst() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        isRevealed = false
        showOriginal = false
    }

    /// Replaces the first card with `fresh` when it is still `cardId`. Drops it when `fresh` is nil (missing), or
    /// when it is suspended and `dropSuspended` is set.
    private func replaceFirst(with fresh: ReviewCardItem?, cardId: String, dropSuspended: Bool) {
        guard queue.first?.id == cardId else { return }
        guard let fresh, !(dropSuspended && fresh.card.suspended) else {
            dropFirst()
            return
        }
        queue[0] = fresh
    }

    /// Loads the themed review's plan. Zero cards completes the review at once (ADR-0022) and finishes with a zero
    /// summary. A completion error goes to `errorMessage`; the summary still shows.
    private func loadThemedPlan(reviewId: String) async {
        do {
            let loaded = try await environment.reviewService.themedPlan(reviewId: reviewId)
            themedReviewName = loaded.review.name
            if loaded.cardIds.isEmpty {
                resetCounters()
                plan = nil
                do {
                    try await environment.reviewService.completeThemedReview(id: reviewId)
                } catch {
                    Log.app.error("Themed review completion failed: \(String(describing: error), privacy: .public)")
                    errorMessage = "The themed review couldn't be marked completed."
                }
                phase = .finished(await makeSummary())
                return
            }
            plan = DailyReviewPlan(cardIds: loaded.cardIds, dueCount: loaded.cardIds.count, newCount: 0)
            phase = .ready(dueCount: loaded.cardIds.count, newCount: 0)
        } catch {
            Log.app.error("Themed plan failed to load: \(String(describing: error), privacy: .public)")
            phase = .failed(
                (error as? ThemedReviewError)?.errorDescription ?? "The review plan couldn't be loaded."
            )
        }
    }

    /// Finishes when the queue is empty. Only a rating completes a themed review (`completingThemed`), so a
    /// session that empties through a drop or a frequency change ends without completion. A completion error goes
    /// to `errorMessage`; the summary still shows.
    private func finishIfEmpty(completingThemed: Bool = false) async {
        guard phase == .reviewing, queue.isEmpty else { return }
        if completingThemed, let reviewId = context.themedReviewId {
            do {
                try await environment.reviewService.completeThemedReview(id: reviewId)
            } catch {
                Log.app.error("Themed review completion failed: \(String(describing: error), privacy: .public)")
                errorMessage = "The themed review couldn't be marked completed."
            }
        }
        phase = .finished(await makeSummary())
    }

    private func makeSummary() async -> ReviewSummary {
        let dueTomorrow = (try? await environment.reviewService.dueTomorrowCount()) ?? 0
        let percent = reviewedCount == 0
            ? 0
            : Int((100 * Double(rememberedCount) / Double(reviewedCount)).rounded())
        return ReviewSummary(
            reviewed: reviewedCount,
            remembered: rememberedCount,
            rememberedPercent: percent,
            dueTomorrow: dueTomorrow
        )
    }
}
