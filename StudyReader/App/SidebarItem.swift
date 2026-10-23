import Foundation

/// Top-level sections shown in the main sidebar (SPEC F-01). Order is significant.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable, Sendable {
    case library
    case highlights
    case review
    case themedReviews
    case tags
    case categories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .highlights: String(localized: "Highlights")
        case .review: String(localized: "Review")
        case .themedReviews: String(localized: "Themed Reviews")
        case .tags: String(localized: "Tags")
        case .categories: String(localized: "Categories")
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .highlights: "highlighter"
        case .review: "rectangle.stack"
        case .themedReviews: "calendar.badge.clock"
        case .tags: "tag"
        case .categories: "folder"
        }
    }
}
