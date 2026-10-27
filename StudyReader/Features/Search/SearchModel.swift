import Foundation
import Observation

/// State of the global search (SPEC F-12): query, filters and grouped results. Typing is debounced through the
/// injected `Sleeper`; Return and filter changes run through `searchNow()` / the same debounce.
@MainActor @Observable
final class SearchModel {
    static let debounceDelay: Duration = .milliseconds(150)

    var query: String = "" {
        didSet {
            if query != oldValue {
                scheduleSearch()
            }
        }
    }

    var filters = SearchFilters() {
        didSet {
            if filters != oldValue {
                scheduleSearch()
            }
        }
    }

    private(set) var results = SearchResults()
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    /// Choices for the filter menus, kept current by `observeTags()` and `observeCategories()`.
    private(set) var tags: [LibraryTag] = []
    private(set) var categories: [DocumentCategory] = []

    /// True while the trimmed query isn't empty. The results replace the detail column then.
    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ObservationIgnored private let service: SearchService
    @ObservationIgnored private let tagRepository: TagRepository
    @ObservationIgnored private let categoryRepository: CategoryRepository
    @ObservationIgnored private let debouncer: Debouncer
    /// Bumped by every search start and by clearing. A finished search is applied only if this is unchanged.
    @ObservationIgnored private var generation = 0

    init(environment: AppEnvironment) {
        self.service = environment.searchService
        self.tagRepository = environment.tagRepository
        self.categoryRepository = environment.categoryRepository
        self.debouncer = Debouncer(delay: Self.debounceDelay, sleeper: environment.sleeper)
    }

    /// Runs the search with the current query and filters now (Return key, tests). An inactive query clears the results.
    func searchNow() async {
        await debouncer.cancel()
        generation += 1
        let current = generation
        guard isActive else {
            results = SearchResults()
            isSearching = false
            errorMessage = nil
            return
        }
        let text = query
        let activeFilters = filters
        isSearching = true
        errorMessage = nil
        do {
            let found = try await service.search(text, filters: activeFilters)
            guard current == generation else { return }
            results = found
        } catch {
            guard current == generation else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "The search couldn't run. Try again.")
        }
        isSearching = false
    }

    /// Runs the tag list for the filter menu until cancelled.
    func observeTags() async {
        do {
            for try await observed in tagRepository.observeAll() {
                tags = observed
            }
        } catch {
            Log.database.error("The tag list for the search filters stopped updating.")
        }
    }

    /// Runs the category list for the filter menu until cancelled.
    func observeCategories() async {
        do {
            for try await observed in categoryRepository.observeAll() {
                categories = observed
            }
        } catch {
            Log.database.error("The category list for the search filters stopped updating.")
        }
    }

    /// Empties the query and the filters.
    func clear() {
        query = ""
        filters = SearchFilters()
    }

    // MARK: - Locations (ADR-0017)

    /// Where a document hit opens: the matching page or section for text hits, nothing for title or author hits.
    nonisolated static func location(for hit: DocumentHit, query: String) -> ReaderLocation? {
        guard hit.field == .text, let unitIndex = hit.unitIndex else { return nil }
        return .searchHit(unitIndex: unitIndex, query: query)
    }

    nonisolated static func location(for hit: HighlightHit) -> ReaderLocation {
        .highlight(hit.highlightId)
    }

    nonisolated static func location(for hit: NoteHit) -> ReaderLocation {
        if hit.kind == .highlightNote, let highlightId = hit.highlightId {
            return .highlight(highlightId)
        }
        return .documentNote
    }

    // MARK: - Debounce

    /// The action reads the query when it runs, so the order in which rapid edits reach the debouncer doesn't matter.
    private func scheduleSearch() {
        generation += 1
        guard isActive else {
            results = SearchResults()
            isSearching = false
            errorMessage = nil
            let debouncer = debouncer
            Task { await debouncer.cancel() }
            return
        }
        let debouncer = debouncer
        Task { [weak self] in
            guard let self else { return }
            await debouncer.schedule { [weak self] in
                await self?.searchNow()
            }
        }
    }
}

/// Splits a snippet on "**" and bolds the odd segments (the match).
nonisolated func attributedSnippet(_ snippet: String) -> AttributedString {
    var result = AttributedString()
    for (index, part) in snippet.components(separatedBy: "**").enumerated() where !part.isEmpty {
        var piece = AttributedString(part)
        if index % 2 == 1 {
            piece.inlinePresentationIntent = .stronglyEmphasized
        }
        result += piece
    }
    return result
}
