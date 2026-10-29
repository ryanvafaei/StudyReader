import Foundation
import GRDB

/// What the themed review editor (T123) hands over. Validated by `ThemedReviewRepository.create` and `update`.
struct ThemedReviewDraft: Sendable, Equatable {
    var name: String
    var filter: ThemedReviewFilter = ThemedReviewFilter()
    var cardsPerSession: Int = 20
    var interval: ReviewInterval = .daily
    var orderMode: ReviewOrderMode = .dueFirst

    init(
        name: String,
        filter: ThemedReviewFilter = ThemedReviewFilter(),
        cardsPerSession: Int = 20,
        interval: ReviewInterval = .daily,
        orderMode: ReviewOrderMode = .dueFirst
    ) {
        self.name = name
        self.filter = filter
        self.cardsPerSession = cardsPerSession
        self.interval = interval
        self.orderMode = orderMode
    }

    /// Copies the editable fields of a stored review.
    init(_ review: ThemedReview) {
        self.init(
            name: review.name,
            filter: review.filter,
            cardsPerSession: review.cardsPerSession,
            interval: review.interval,
            orderMode: review.orderMode
        )
    }
}

enum ThemedReviewError: Error, Equatable, LocalizedError {
    case emptyName
    case nameTooLong
    case invalidCardsPerSession
    case invalidInterval
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .nameTooLong: "Names can have at most 80 characters."
        case .invalidCardsPerSession: "Cards per session must be between 5 and 100."
        case .invalidInterval: "Choose an interval: every 1 to 365 days, or at least one weekday."
        case .notFound: "This themed review no longer exists."
        }
    }
}

/// The candidates of a themed review and the cards already rated today.
struct ThemedQueueSnapshot: Sendable, Equatable {
    /// Not suspended cards whose highlight matches the filter (any state, due or not). Ordered cardId ASC.
    var candidates: [ReviewQueueEntry]
    /// Cards rated since dayStart in any session (ARCHITECTURE §10.2: excluded from the themed session).
    var ratedTodayCardIds: Set<String>
}

extension ThemedReviewFilter {
    /// The browser filter for this themed filter. Export's themed-review scope uses the same mapping.
    var highlightBrowserFilter: HighlightBrowserFilter {
        HighlightBrowserFilter(
            documentIds: Set(documentIds),
            categoryIds: Set(categoryIds),
            tagIds: Set(tagIds),
            tagMode: tagMode,
            colors: Set(colors)
        )
    }
}

/// Stores themed reviews (SPEC F-20, ADR-0022). Every multi-row change is one transaction; writes never upsert.
struct ThemedReviewRepository: Sendable {
    static let cardsPerSessionRange = 5...100
    static let maxNameLength = 80

    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    // MARK: Reads

    /// Ordered by name (localized case-insensitive), then id; same order as ExportRepository.fetchThemedReviews.
    func fetchAll() async throws -> [ThemedReview] {
        try await writer.read { db in
            try Self.allReviews(db)
        }
    }

    func observeAll() -> AsyncValueObservation<[ThemedReview]> {
        ValueObservation
            .tracking { db in
                try Self.allReviews(db)
            }
            .values(in: writer)
    }

    func fetch(id: String) async throws -> ThemedReview? {
        try await writer.read { db in
            try ThemedReview.fetchOne(db, key: id)
        }
    }

    /// One read. The filter becomes a HighlightBrowserFilter and the candidates come from `ReviewQueueSQL.themedQueue`.
    func themedQueue(filter: ThemedReviewFilter, dayStart: Date) async throws -> ThemedQueueSnapshot {
        try await writer.read { db in
            try ReviewQueueSQL.themedQueue(db, filter: filter.highlightBrowserFilter, dayStart: dayStart)
        }
    }

    // MARK: Writes

    /// Validates, then inserts with a new id, `createdAt` = date and no completion.
    func create(_ draft: ThemedReviewDraft, at date: Date) async throws -> ThemedReview {
        let fields = try Self.validated(draft)
        let review = ThemedReview(
            id: UUID().uuidString,
            name: fields.name,
            filter: fields.filter,
            cardsPerSession: fields.cardsPerSession,
            interval: fields.interval,
            orderMode: fields.orderMode,
            lastCompletedAt: nil,
            createdAt: date.storageRounded
        )
        try await writer.write { db in
            try review.insert(db)
        }
        return review
    }

    /// Validates, then updates the editable columns only. `lastCompletedAt` stays as it is.
    /// Missing row: `ThemedReviewError.notFound`.
    func update(id: String, _ draft: ThemedReviewDraft) async throws {
        let fields = try Self.validated(draft)
        try await writer.write { db in
            guard var review = try ThemedReview.fetchOne(db, key: id) else {
                throw ThemedReviewError.notFound
            }
            review.name = fields.name
            review.filter = fields.filter
            review.cardsPerSession = fields.cardsPerSession
            review.interval = fields.interval
            review.orderMode = fields.orderMode
            try review.update(db, columns: ["name", "filter", "cardsPerSession", "interval", "orderMode"])
        }
    }

    /// Copy named "<name> copy" (cut to `maxNameLength` characters), new id, `createdAt` = date, no completion.
    /// Missing row: `ThemedReviewError.notFound`.
    func duplicate(id: String, at date: Date) async throws -> ThemedReview {
        try await writer.write { db in
            guard let original = try ThemedReview.fetchOne(db, key: id) else {
                throw ThemedReviewError.notFound
            }
            let copy = ThemedReview(
                id: UUID().uuidString,
                name: String((original.name + " copy").prefix(Self.maxNameLength)),
                filter: original.filter,
                cardsPerSession: original.cardsPerSession,
                interval: original.interval,
                orderMode: original.orderMode,
                lastCompletedAt: nil,
                createdAt: date.storageRounded
            )
            try copy.insert(db)
            return copy
        }
    }

    /// Review logs keep their rows: the schema sets `themedReviewId` to NULL. Returns false when the review is missing.
    @discardableResult
    func delete(id: String) async throws -> Bool {
        try await writer.write { db in
            try ThemedReview.deleteOne(db, key: id)
        }
    }

    /// Sets `lastCompletedAt` (column-limited). Missing row: `ThemedReviewError.notFound`.
    func markCompleted(id: String, at date: Date) async throws {
        try await writer.write { db in
            guard var review = try ThemedReview.fetchOne(db, key: id) else {
                throw ThemedReviewError.notFound
            }
            review.lastCompletedAt = date.storageRounded
            try review.update(db, columns: ["lastCompletedAt"])
        }
    }

    // MARK: Helpers

    private struct ValidatedFields {
        var name: String
        var filter: ThemedReviewFilter
        var cardsPerSession: Int
        var interval: ReviewInterval
        var orderMode: ReviewOrderMode
    }

    /// Trims and checks the name, checks the session size, and normalizes the interval (ARCHITECTURE §10).
    private static func validated(_ draft: ThemedReviewDraft) throws -> ValidatedFields {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ThemedReviewError.emptyName }
        guard name.count <= maxNameLength else { throw ThemedReviewError.nameTooLong }
        guard cardsPerSessionRange.contains(draft.cardsPerSession) else {
            throw ThemedReviewError.invalidCardsPerSession
        }
        return ValidatedFields(
            name: name,
            filter: draft.filter,
            cardsPerSession: draft.cardsPerSession,
            interval: try normalizedInterval(draft.interval),
            orderMode: draft.orderMode
        )
    }

    private static func normalizedInterval(_ interval: ReviewInterval) throws -> ReviewInterval {
        switch interval.kind {
        case .daily:
            return .daily
        case .everyNDays:
            guard let n = interval.n, (1...365).contains(n) else { throw ThemedReviewError.invalidInterval }
            return .everyNDays(n)
        case .weekdays:
            let days = Set(interval.weekdays ?? [])
            guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
                throw ThemedReviewError.invalidInterval
            }
            return .weekdays(days.sorted())
        }
    }

    /// Name ascending (localized case-insensitive), then id.
    private static func allReviews(_ db: Database) throws -> [ThemedReview] {
        try ThemedReview
            .order(Column("name").collating(.localizedCaseInsensitiveCompare), Column("id"))
            .fetchAll(db)
    }
}
