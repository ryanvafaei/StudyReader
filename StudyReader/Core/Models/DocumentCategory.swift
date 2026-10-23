import Foundation

/// `category` table (ARCHITECTURE §4).
struct DocumentCategory: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "category"

    var id: String
    var name: String
    var isBuiltin: Bool = false
    var frequency: ReviewFrequency = .normal
    var autoCreateCards: Bool = true
    var sortOrder: Int = 0
}
