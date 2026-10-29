import Foundation

/// The review screen's count texts. The catalog holds the plural variations (T109).
enum ReviewStrings {
    /// "1 card to review" / "N cards to review".
    nonisolated static func cardsToReview(_ count: Int) -> String {
        String(localized: "\(count) cards to review")
    }

    /// "Reviewed 1 card" / "Reviewed N cards".
    nonisolated static func reviewed(_ count: Int) -> String {
        String(localized: "Reviewed \(count) cards")
    }

    /// "N due · M new".
    nonisolated static func dueAndNew(due: Int, new: Int) -> String {
        String(localized: "\(due) due · \(new) new")
    }
}
