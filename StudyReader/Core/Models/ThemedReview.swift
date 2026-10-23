import Foundation

/// `themedReview` table (ARCHITECTURE §4). `filter` and `interval` are JSON columns.
struct ThemedReview: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "themedReview"

    var id: String
    var name: String
    var filter: ThemedReviewFilter = ThemedReviewFilter()
    var cardsPerSession: Int = 20
    var interval: ReviewInterval = .daily
    var orderMode: ReviewOrderMode = .dueFirst
    var lastCompletedAt: Date? = nil
    var createdAt: Date
}
