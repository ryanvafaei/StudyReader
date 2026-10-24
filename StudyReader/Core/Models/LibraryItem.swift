import Foundation

/// One row of the library list (SPEC F-01).
struct LibraryItem: Sendable, Equatable, Identifiable {
    var document: LibraryDocument
    var categoryName: String
    var highlightCount: Int
    var tagIds: [String]          // sorted ascending
    var id: String { document.id }
}

/// Shared by repositories.
enum RepositoryError: Error, Equatable { case notFound }
