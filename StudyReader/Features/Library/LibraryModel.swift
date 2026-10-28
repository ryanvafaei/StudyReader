import AppKit
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

    /// Cover file modification date per document id, refreshed on every observed list change. Documents without a
    /// cover file are absent. The grid reloads a card's cover when its date changes, because `CoverService`
    /// overwrites `cover.png` in place and `coverPath` stays the same.
    private(set) var coverVersions: [String: Date] = [:]

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

    /// Categories for the filter menu, from `CategoryRepository.observeAll()`.
    private(set) var categories: [DocumentCategory] = []

    /// Tags for the filter menu, from `TagRepository.observeAll()`.
    private(set) var tags: [LibraryTag] = []

    /// User-facing message from the last failed observation, delete or retry. Nil after a successful delete.
    private(set) var errorMessage: String?

    /// Latest run number of each observation loop; a run whose number is no longer current must not assign.
    @ObservationIgnored private var documentsGeneration = 0
    @ObservationIgnored private var categoriesGeneration = 0
    @ObservationIgnored private var tagsGeneration = 0

    @ObservationIgnored private let documents: DocumentRepository
    @ObservationIgnored private let categoryRepository: CategoryRepository
    @ObservationIgnored private let tagRepository: TagRepository
    @ObservationIgnored private let fileStore: FileStore
    @ObservationIgnored private let extractionService: ExtractionService
    @ObservationIgnored private let settingsStore: SettingsStore

    init(environment: AppEnvironment) {
        self.documents = environment.documentRepository
        self.categoryRepository = environment.categoryRepository
        self.tagRepository = environment.tagRepository
        self.fileStore = environment.fileStore
        self.extractionService = environment.extractionService
        self.settingsStore = environment.settingsStore
        self.sort = environment.settingsStore.librarySort
        self.layout = environment.settingsStore.libraryLayout
    }

    /// Runs the live list until the calling task is cancelled (`.task {}` in the view).
    ///
    /// SwiftUI can restart the view's `.task`. A cancelled run may still deliver one buffered emission after the
    /// new run delivered a newer one, so each run takes a generation token and assigns only while it is the latest
    /// and not cancelled.
    func observe() async {
        documentsGeneration += 1
        let generation = documentsGeneration
        do {
            for try await observed in documents.observeItems() {
                guard generation == documentsGeneration, !Task.isCancelled else { break }
                // CoverService replaces the file before it updates the row, so this emission sees the new date.
                coverVersions = Self.coverVersions(for: observed, fileStore: fileStore)
                items = observed
            }
        } catch {
            guard generation == documentsGeneration, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Runs the category list for the filter menu until cancelled. Stale runs never assign (see `observe()`).
    func observeCategories() async {
        categoriesGeneration += 1
        let generation = categoriesGeneration
        do {
            for try await observed in categoryRepository.observeAll() {
                guard generation == categoriesGeneration, !Task.isCancelled else { break }
                categories = observed
            }
        } catch {
            guard generation == categoriesGeneration, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Runs the tag list for the filter menu until cancelled. Stale runs never assign (see `observe()`).
    func observeTags() async {
        tagsGeneration += 1
        let generation = tagsGeneration
        do {
            for try await observed in tagRepository.observeAll() {
                guard generation == tagsGeneration, !Task.isCancelled else { break }
                tags = observed
            }
        } catch {
            guard generation == tagsGeneration, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Deletes the document row and its folder. The observed list drops the row on its own.
    func delete(documentId: String) async {
        do {
            _ = try await documents.delete(id: documentId, fileStore: fileStore)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Queues the document for text extraction again.
    func retryExtraction(documentId: String) async {
        await extractionService.enqueue(documentId: documentId)
    }

    /// The selected id when that document is still listed, otherwise nil. The view reads this instead of
    /// clearing its selection on every list change, so bulk updates don't write state back into the view.
    func existingSelection(_ id: String?) -> String? {
        guard let id, items.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Clears the alert message once the user has seen it.
    func dismissError() {
        errorMessage = nil
    }

    /// Resolves the bookmark of the original file without mounting volumes or showing UI.
    /// Returns nil when the document has no bookmark or the file is no longer there.
    func resolveOriginal(of document: LibraryDocument) -> URL? {
        guard let bookmark = document.originalBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    /// Selects the original file in Finder. Sets `errorMessage` when the original can't be found.
    func revealOriginal(of document: LibraryDocument) {
        guard let url = resolveOriginal(of: document) else {
            errorMessage = String(localized: "The original file is no longer available.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Reads `.contentModificationDateKey` of each item's cover file (`fileStore.url(forRelativePath: coverPath)`).
    /// Items with no `coverPath`, an unresolvable path or no file are skipped. Pure apart from reading file metadata.
    nonisolated static func coverVersions(for items: [LibraryItem], fileStore: FileStore) -> [String: Date] {
        var versions: [String: Date] = [:]
        for item in items {
            guard let coverPath = item.document.coverPath,
                  let url = fileStore.url(forRelativePath: coverPath),
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            versions[item.id] = modified
        }
        return versions
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
