import AppKit
import Foundation
import Observation

/// What the browser's live list depends on. The view restarts `observe()` when it changes (`.task(id:)`).
struct HighlightBrowseQuery: Equatable {
    var filter: HighlightBrowserFilter
    var sort: HighlightBrowserSort
}

/// State behind the Highlights section (SPEC F-13, without Similar and Mastery): the live list for a filter and
/// sort, the multi-selection, bulk actions and cached snapshot images.
@MainActor @Observable
final class HighlightsBrowserModel {
    var filter = HighlightBrowserFilter()
    var sort: HighlightBrowserSort = .createdNewest
    /// Ids of the selected rows. Pruned to the rows that still exist.
    var selection: Set<String> = []

    private(set) var items: [HighlightListItem] = []
    /// false until the list has been read once, so the empty state doesn't flash while loading.
    private(set) var hasLoaded = false
    /// Options for the filter menus.
    private(set) var documents: [LibraryDocument] = []
    private(set) var categories: [DocumentCategory] = []
    private(set) var tags: [LibraryTag] = []
    /// Snapshot images by relative image path, loaded once so views never read files while drawing (B15).
    private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var errorMessage: String?
    /// Outcome of "Export Selection…", shown in an alert.
    private(set) var exportMessage: String?
    /// true while `exportSelection()` runs, so a double click can't start two exports.
    private(set) var isExporting = false

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let calendar: Calendar

    init(environment: AppEnvironment, calendar: Calendar = .current) {
        self.environment = environment
        self.calendar = calendar
    }

    var query: HighlightBrowseQuery { HighlightBrowseQuery(filter: filter, sort: sort) }

    var isFiltered: Bool { filter != HighlightBrowserFilter() }

    /// The selected rows in list order.
    var selectedItems: [HighlightListItem] { items.filter { selection.contains($0.id) } }

    /// The row the detail pane shows: only when exactly one row is selected.
    var detailItem: HighlightListItem? {
        selection.count == 1 ? items.first { selection.contains($0.id) } : nil
    }

    /// Tags carried by at least one selected highlight, in name order.
    var tagsInSelection: [LibraryTag] {
        let ids = Set(selectedItems.flatMap(\.tagIds))
        return tags.filter { ids.contains($0.id) }
    }

    // MARK: - Text

    /// "0 highlights", "1 highlight", "N highlights": one String Catalog entry with plural variations, so the noun
    /// agrees with the count.
    nonisolated static func countText(_ count: Int) -> String {
        String(localized: "\(count) highlights")
    }

    /// Title of the delete confirmation: "Delete 1 highlight?" / "Delete N highlights?", from one plural catalog entry.
    nonisolated static func deleteTitle(count: Int) -> String {
        String(localized: "Delete \(count) highlights?")
    }

    // MARK: - Export

    /// One-off export of the selected highlights to a new Google Doc. No export target is created.
    func exportSelection() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        let outcome = await environment.googleExportService.exportSelection(
            highlightIds: Array(selection),
            options: ExportOptions()
        )
        exportMessage = ExportSheetModel.message(for: outcome)
    }

    func dismissExportMessage() {
        exportMessage = nil
    }

    // MARK: - Observation

    /// Streams the list for the current filter and sort until the calling task is cancelled.
    func observe() async {
        let observation = environment.highlightRepository.observeBrowse(filter: filter, sort: sort)
        do {
            for try await list in observation {
                items = list
                hasLoaded = true
                let existing = Set(list.map(\.id))
                if !selection.isSubset(of: existing) {
                    selection.formIntersection(existing)
                }
                await loadThumbnails(for: list)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "The highlights couldn't be loaded.")
        }
    }

    /// Streams the documents, categories and tags that the filter menus offer.
    func observeLookups() async {
        async let documents: Void = observeDocuments()
        async let categories: Void = observeCategories()
        async let tags: Void = observeTags()
        _ = await (documents, categories, tags)
    }

    private func observeDocuments() async {
        do {
            for try await list in environment.documentRepository.observeAll() {
                documents = list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        } catch {}
    }

    private func observeCategories() async {
        do {
            for try await list in environment.categoryRepository.observeAll() {
                categories = list
            }
        } catch {}
    }

    private func observeTags() async {
        do {
            for try await list in environment.tagRepository.observeAll() {
                tags = list
            }
        } catch {}
    }

    private func loadThumbnails(for list: [HighlightListItem]) async {
        let fileStore = environment.fileStore
        let paths = Set(list.compactMap { $0.highlight.imagePath })
        var loaded: [String: NSImage] = [:]
        for path in paths {
            if let existing = thumbnails[path] {
                loaded[path] = existing
                continue
            }
            guard let url = fileStore.url(forRelativePath: path) else { continue }
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            if let data, let image = NSImage(data: data) {
                loaded[path] = image
            }
        }
        // A cancelled observation (the filter changed meanwhile) must not overwrite what its successor loaded.
        guard !Task.isCancelled else { return }
        thumbnails = loaded
    }

    // MARK: - Filters

    func clearFilters() {
        filter = HighlightBrowserFilter()
    }

    func toggle(documentId: String) { Self.toggle(documentId, in: &filter.documentIds) }
    func toggle(categoryId: String) { Self.toggle(categoryId, in: &filter.categoryIds) }
    func toggle(tagId: String) { Self.toggle(tagId, in: &filter.tagIds) }
    func toggle(color: HighlightColor) { Self.toggle(color, in: &filter.colors) }
    func toggle(view: ReaderViewKind) { Self.toggle(view, in: &filter.views) }

    private static func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// First day of the range (inclusive), or nil. Setting it keeps the start of that day.
    var fromDay: Date? {
        get { filter.createdFrom }
        set { filter.createdFrom = newValue.map { calendar.startOfDay(for: $0) } }
    }

    /// Last day of the range (inclusive), or nil. The filter's exclusive bound is the start of the next day.
    var toDay: Date? {
        get {
            filter.createdBefore.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        }
        set {
            filter.createdBefore = newValue.flatMap {
                calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
            }
        }
    }

    /// Today as the injected clock sees it; the date pickers start here when a bound is switched on.
    var today: Date { environment.now() }

    // MARK: - Bulk actions (apply to the selection)

    /// Adds the tag, creating it when no tag has this name (case-insensitive), to every selected highlight.
    func addTag(named name: String) async {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Array(selection)
        guard !clean.isEmpty, !ids.isEmpty else { return }
        do {
            let tag = try await environment.tagRepository.findOrCreate(name: clean, at: environment.now())
            try await environment.tagRepository.addTag(tag.id, toHighlights: ids)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The tag couldn't be added.")
        }
    }

    func removeTag(_ tagId: String) async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        do {
            try await environment.tagRepository.removeTag(tagId, fromHighlights: ids)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The tag couldn't be removed.")
        }
    }

    func setColor(_ color: HighlightColor) async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        do {
            try await environment.highlightService.setColor(ids: ids, color: color)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The color couldn't be changed.")
        }
    }

    func deleteSelected() async {
        await delete(ids: selection)
    }

    func delete(ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        do {
            try await environment.highlightService.delete(ids: Array(ids))
            selection.subtract(ids)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The highlights couldn't be deleted.")
        }
    }

    /// Tag suggestions for the bulk "Add Tag" field: existing tags starting with the query.
    func suggestions(for query: String) -> [LibraryTag] {
        TagFieldModel.suggestions(for: query, in: tags, excluding: [])
    }
}

extension Highlight {
    /// Markdown shown for a browser row: the edited text, else the rich text, else the plain text.
    var listExcerptMarkdown: String {
        if let editedText { return RichTextMarkdown.escape(editedText) }
        return richText.isEmpty ? RichTextMarkdown.escape(text) : richText
    }

    /// Row label for VoiceOver and UI tests: the plain excerpt, or "Snapshot" for an image highlight.
    var listAccessibilityExcerpt: String {
        if imagePath != nil { return String(localized: "Snapshot") }
        let plain = editedText ?? text
        return plain.isEmpty ? String(localized: "Highlight") : plain
    }
}
