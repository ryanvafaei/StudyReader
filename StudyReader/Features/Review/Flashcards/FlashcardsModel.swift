import Foundation
import Observation

/// State behind the Flashcards section (SPEC F-17, ADR-0022): the live card list for a filter, the selected card and
/// its frequency and text edits. Actions go only through `ReviewService`. No rating and no Skip (README Q3).
@MainActor @Observable
final class FlashcardsModel {
    var filter = FlashcardFilter()
    /// Id of the selected card. Pruned when the card leaves the list.
    var selection: String?
    /// Show the original text of a passive card instead of its excerpt (F-17 "Show original").
    var showOriginal = false
    /// Highlight id the Mastery editor is shown for (sheet over the Flashcards view).
    var masteryHighlightId: String?

    private(set) var items: [FlashcardItem] = []
    /// false until the list has been read once, so the empty state doesn't flash while loading.
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    /// Options for the filter menus.
    private(set) var documents: [LibraryDocument] = []
    private(set) var categories: [DocumentCategory] = []
    private(set) var tags: [LibraryTag] = []

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let calendar: Calendar
    /// Incremented by every `observe()` call. A run whose generation is no longer current drops its values, so a
    /// superseded observation can't overwrite the list of the filter that replaced it.
    @ObservationIgnored private var observeGeneration = 0

    init(environment: AppEnvironment, calendar: Calendar = .current) {
        self.environment = environment
        self.calendar = calendar
    }

    var isFiltered: Bool { filter != FlashcardFilter() }

    /// The row the detail pane shows.
    var selectedItem: FlashcardItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    /// What the detail pane renders for the selected card.
    var selectedContent: ReviewCardContent? {
        selectedItem.map { ReviewCardContent.make($0.item, showOriginal: showOriginal) }
    }

    // MARK: - Text

    /// "0 cards", "1 card", "N cards": one String Catalog entry with plural variations.
    nonisolated static func countText(_ count: Int) -> String {
        String(localized: "\(count) cards")
    }

    // MARK: - Observation

    /// Streams the cards for the current filter until the calling task is cancelled. Starting a new run supersedes
    /// the earlier ones; their late values are ignored.
    func observe() async {
        observeGeneration += 1
        let generation = observeGeneration
        let observation = environment.reviewCardRepository.observeFlashcards(filter: filter)
        do {
            for try await list in observation {
                guard generation == observeGeneration, !Task.isCancelled else { return }
                items = list
                hasLoaded = true
                if let selection, !list.contains(where: { $0.id == selection }) {
                    self.selection = nil
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == observeGeneration else { return }
            errorMessage = String(localized: "The cards couldn't be loaded.")
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

    // MARK: - Filters

    func clearFilters() {
        filter = FlashcardFilter()
    }

    func toggle(state: FlashcardState) { Self.toggle(state, in: &filter.states) }
    func toggle(cardType: CardType) { Self.toggle(cardType, in: &filter.cardTypes) }
    func toggle(documentId: String) { Self.toggle(documentId, in: &filter.documentIds) }
    func toggle(categoryId: String) { Self.toggle(categoryId, in: &filter.categoryIds) }
    func toggle(tagId: String) { Self.toggle(tagId, in: &filter.tagIds) }

    private static func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// First day of the due range (inclusive), or nil. Setting it keeps the start of that day.
    var dueFromDay: Date? {
        get { filter.dueFrom }
        set { filter.dueFrom = newValue.map { calendar.startOfDay(for: $0) } }
    }

    /// Last day of the due range (inclusive), or nil. The filter's exclusive bound is the start of the next day.
    var dueToDay: Date? {
        get {
            filter.dueBefore.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        }
        set {
            filter.dueBefore = newValue.flatMap {
                calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
            }
        }
    }

    // MARK: - Actions on the selected card

    /// Sets the card's frequency override (nil follows the category). Off suspends the card.
    func setFrequency(_ override: ReviewFrequency?) async {
        guard let card = selectedItem?.item.card else { return }
        do {
            try await environment.reviewService.setFrequencyOverride(cardId: card.id, override)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The frequency couldn't be changed.")
        }
    }

    /// Replaces the selected card's highlight text (nil restores the original). Cards built from the highlight follow.
    func editHighlightText(_ text: String?) async {
        guard let highlightId = selectedItem?.item.highlight.id else { return }
        do {
            try await environment.reviewService.editHighlightText(highlightId: highlightId, text)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The highlight couldn't be changed.")
        }
    }
}
