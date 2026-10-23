import Foundation

/// The five categories seeded by migration `v1` (ARCHITECTURE §4). Fixed IDs; names are stored data, not localized.
enum BuiltinCategory: String, CaseIterable, Sendable {
    case lectureSlides, paper, bookChapter, notes, other

    var id: String {
        switch self {
        case .lectureSlides: "00000000-0000-0000-0000-000000000001"
        case .paper: "00000000-0000-0000-0000-000000000002"
        case .bookChapter: "00000000-0000-0000-0000-000000000003"
        case .notes: "00000000-0000-0000-0000-000000000004"
        case .other: "00000000-0000-0000-0000-000000000005"
        }
    }

    var name: String {
        switch self {
        case .lectureSlides: "Lecture slides"
        case .paper: "Paper"
        case .bookChapter: "Book chapter"
        case .notes: "Notes"
        case .other: "Other"
        }
    }

    var frequency: ReviewFrequency {
        switch self {
        case .lectureSlides: .high
        case .paper, .bookChapter, .other: .normal
        case .notes: .low
        }
    }

    var sortOrder: Int {
        switch self {
        case .lectureSlides: 0
        case .paper: 1
        case .bookChapter: 2
        case .notes: 3
        case .other: 4
        }
    }
}
