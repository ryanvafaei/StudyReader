import Foundation

/// Settings > Review values (SPEC F-15 defaults 15 and 5). AppSettings.dailyLimits builds it (T106).
struct DailyLimits: Sendable, Equatable {
    var dailyLimit: Int
    var newPerDay: Int

    static let defaults = DailyLimits(dailyLimit: 15, newPerDay: 5)
}

struct DailyReviewPlan: Sendable, Equatable {
    /// Due cards first, then new cards.
    var cardIds: [String]
    var dueCount: Int
    var newCount: Int

    var isEmpty: Bool { cardIds.isEmpty }
}

/// Picks today's daily session from the repository snapshot (SPEC F-15, ADR-0022). Pure: no clock, no database.
enum DailyReviewBuilder {
    static func build(_ snapshot: DailyQueueSnapshot, limits: DailyLimits) -> DailyReviewPlan {
        let activity = snapshot.activity
        let rated = activity.ratedCardIds

        // Budgets are per review day. Cards rated today in daily sessions that were not introduced today
        // already used up part of the due budget; cards introduced today used up the new budget.
        let ratedDueToday = activity.dailyRatedCardIds.subtracting(activity.introducedCardIds).count
        let dueBudget = max(0, limits.dailyLimit - ratedDueToday)
        let newBudget = max(0, limits.newPerDay - activity.introducedCardIds.count)

        let dueCards = snapshot.due
            .filter { !rated.contains($0.cardId) }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt { return lhs.dueAt < rhs.dueAt }
                return lhs.cardId < rhs.cardId
            }
            .prefix(dueBudget)

        let newCards = snapshot.new
            .filter { !rated.contains($0.cardId) }
            .sorted { lhs, rhs in
                if lhs.highlightCreatedAt != rhs.highlightCreatedAt {
                    return lhs.highlightCreatedAt < rhs.highlightCreatedAt
                }
                let lhsRank = typeRank(lhs.cardType)
                let rhsRank = typeRank(rhs.cardType)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.cardId < rhs.cardId
            }
            .prefix(newBudget)

        let dueIds = dueCards.map(\.cardId)
        let newIds = newCards.map(\.cardId)
        return DailyReviewPlan(
            cardIds: dueIds + newIds,
            dueCount: dueIds.count,
            newCount: newIds.count
        )
    }

    /// Passive first, then cloze, then Q&A (ADR-0021 card types).
    private static func typeRank(_ type: CardType) -> Int {
        switch type {
        case .passive: 0
        case .cloze: 1
        case .qa: 2
        }
    }
}
