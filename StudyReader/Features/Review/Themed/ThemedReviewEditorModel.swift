import Foundation
import Observation

/// State behind the themed review editor sheet (SPEC F-20): the draft, the picker lookups and saving.
@MainActor @Observable
final class ThemedReviewEditorModel {
    var draft = ThemedReviewDraft(name: "")
    /// false until an existing review has been read (always true for a new review after `load()`).
    private(set) var hasLoaded = false
    /// `ThemedReviewError` text from the last save.
    private(set) var errorMessage: String?
    private(set) var tags: [LibraryTag] = []
    /// Sorted by title.
    private(set) var documents: [LibraryDocument] = []
    private(set) var categories: [DocumentCategory] = []

    @ObservationIgnored private let reviewId: String?
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let calendar: Calendar

    init(reviewId: String?, environment: AppEnvironment, calendar: Calendar = .current) {
        self.reviewId = reviewId
        self.environment = environment
        self.calendar = calendar
    }

    var isNew: Bool { reviewId == nil }

    // MARK: Loading

    func load() async {
        guard !hasLoaded else { return }
        if let reviewId {
            do {
                if let review = try await environment.themedReviewRepository.fetch(id: reviewId) {
                    draft = ThemedReviewDraft(review)
                } else {
                    errorMessage = ThemedReviewError.notFound.errorDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        hasLoaded = true
    }

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

    // MARK: Filter

    func toggle(tagId: String) { Self.toggle(tagId, in: &draft.filter.tagIds) }

    func toggle(documentId: String) { Self.toggle(documentId, in: &draft.filter.documentIds) }

    func toggle(categoryId: String) { Self.toggle(categoryId, in: &draft.filter.categoryIds) }

    func toggle(color: HighlightColor) { Self.toggle(color, in: &draft.filter.colors) }

    private static func toggle<Element: Equatable>(_ element: Element, in list: inout [Element]) {
        if let index = list.firstIndex(of: element) {
            list.remove(at: index)
        } else {
            list.append(element)
        }
    }

    // MARK: Interval

    /// Switching kind starts from n = 1 or today's weekday.
    var intervalKind: ReviewInterval.Kind {
        get { draft.interval.kind }
        set {
            guard newValue != draft.interval.kind else { return }
            switch newValue {
            case .daily:
                draft.interval = .daily
            case .everyNDays:
                draft.interval = .everyNDays(1)
            case .weekdays:
                draft.interval = .weekdays([calendar.component(.weekday, from: environment.now())])
            }
        }
    }

    /// 1...365 (clamped).
    var everyNDays: Int {
        get { draft.interval.n ?? 1 }
        set { draft.interval = .everyNDays(min(max(newValue, 1), 365)) }
    }

    /// Calendar weekday numbers (1 = Sunday) in the calendar's first-weekday order, for the toggles.
    var weekdayOrder: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// Short symbol for a Calendar weekday number.
    func weekdaySymbol(_ weekday: Int) -> String {
        calendar.shortWeekdaySymbols[weekday - 1]
    }

    func isSelected(weekday: Int) -> Bool {
        draft.interval.weekdays?.contains(weekday) ?? false
    }

    func toggle(weekday: Int) {
        guard (1...7).contains(weekday), draft.interval.kind == .weekdays else { return }
        var days = draft.interval.weekdays ?? []
        if let index = days.firstIndex(of: weekday) {
            days.remove(at: index)
        } else {
            days.append(weekday)
        }
        draft.interval = .weekdays(days.sorted())
    }

    // MARK: Saving

    var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() async -> Bool {
        errorMessage = nil
        guard canSave else { return false }
        do {
            if let reviewId {
                try await environment.themedReviewRepository.update(id: reviewId, draft)
            } else {
                _ = try await environment.themedReviewRepository.create(draft, at: environment.now())
            }
            return true
        } catch let error as ThemedReviewError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
