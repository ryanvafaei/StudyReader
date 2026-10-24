import Foundation
import Observation

/// Filters for the library list (SPEC F-01). Every set field must match; unset fields match everything.
struct LibraryFilter: Sendable, Equatable {
    var categoryId: String? = nil
    var tagId: String? = nil
    var fileType: FileType? = nil
    var hasHighlightsOnly: Bool = false

    /// true when any field narrows the list.
    var isActive: Bool {
        categoryId != nil || tagId != nil || fileType != nil || hasHighlightsOnly
    }
}

/// The library screen's logic (SPEC F-01): live list, sort, filter, layout, delete and retry.
/// Views read `visibleItems` and call the actions; they hold no state of their own.
@MainActor @Observable
final class LibraryModel {
    /// Latest observed rows, in the repository's order. Sorting and filtering happen in `visibleItems`.
    private(set) var items: [LibraryItem] = []

    /// `items` filtered by `filter`, then sorted by `sort`.
    var visibleItems: [LibraryItem] {
        Self.sorted(Self.filtered(items, by: filter), by: sort)
    }

    var sort: LibrarySort {
        didSet { settingsStore.librarySort = sort }
    }

    var layout: LibraryLayout {
        didSet { settingsStore.libraryLayout = layout }
    }

    var filter = LibraryFilter()

    /// User-facing message from the last failed observation, delete or retry. Nil after a successful delete.
    private(set) var errorMessage: String?

    @ObservationIgnored private let documents: DocumentRepository
    @ObservationIgnored private let fileStore: FileStore
    @ObservationIgnored private let extractionService: ExtractionService
    @ObservationIgnored private let settingsStore: SettingsStore

    init(environment: AppEnvironment) {
        self.documents = environment.documentRepository
        self.fileStore = environment.fileStore
        self.extractionService = environment.extractionService
        self.settingsStore = environment.settingsStore
        self.sort = environment.settingsStore.librarySort
        self.layout = environment.settingsStore.libraryLayout
    }

    /// Runs the live list until the calling task is cancelled (`.task {}` in the view).
    func observe() async {
        do {
            for try await observed in documents.observeItems() {
                items = observed
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Deletes the document row and its folder. The observed list drops the row on its own.
    func delete(documentId: String) async {
        do {
            try await documents.delete(id: documentId, fileStore: fileStore)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Queues the document for text extraction again.
    func retryExtraction(documentId: String) async {
        await extractionService.enqueue(documentId: documentId)
    }

    /// Ties are always broken by `id` ascending, so the order is total.
    nonisolated static func sorted(_ items: [LibraryItem], by sort: LibrarySort) -> [LibraryItem] {
        items.sorted { lhs, rhs in
            isOrderedBefore(lhs, rhs, by: sort)
        }
    }

    nonisolated static func filtered(_ items: [LibraryItem], by filter: LibraryFilter) -> [LibraryItem] {
        items.filter { item in
            if let categoryId = filter.categoryId, item.document.categoryId != categoryId {
                return false
            }
            if let tagId = filter.tagId, !item.tagIds.contains(tagId) {
                return false
            }
            if let fileType = filter.fileType, item.document.fileType != fileType {
                return false
            }
            if filter.hasHighlightsOnly, item.highlightCount <= 0 {
                return false
            }
            return true
        }
    }

    private nonisolated static func isOrderedBefore(_ lhs: LibraryItem, _ rhs: LibraryItem, by sort: LibrarySort) -> Bool {
        let left = lhs.document
        let right = rhs.document
        switch sort {
        case .dateAdded:
            if left.addedAt != right.addedAt {
                return left.addedAt > right.addedAt
            }
        case .lastOpened:
            switch (left.lastOpenedAt, right.lastOpenedAt) {
            case let (leftOpened?, rightOpened?):
                if leftOpened != rightOpened {
                    return leftOpened > rightOpened
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if left.addedAt != right.addedAt {
                    return left.addedAt > right.addedAt
                }
            }
        case .title:
            let order = left.title.localizedStandardCompare(right.title)
            if order != .orderedSame {
                return order == .orderedAscending
            }
        case .author:
            let leftEmpty = left.author.isEmpty
            let rightEmpty = right.author.isEmpty
            if leftEmpty != rightEmpty {
                return rightEmpty
            }
            if !leftEmpty {
                let order = left.author.localizedStandardCompare(right.author)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
            }
            let titleOrder = left.title.localizedStandardCompare(right.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
        }
        return left.id < right.id
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The library couldn't be updated. Try again.")
    }
}
