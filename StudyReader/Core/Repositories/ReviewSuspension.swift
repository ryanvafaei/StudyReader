import Foundation
import GRDB

/// The only writer of reviewCard.suspended / suspendedReason (ADR-0021). The rule lives in
/// `FrequencyPolicy.suspendedReason(cardType:highlightHasMasteryCards:override:category:)`.
/// Callers run inside their own write transaction.
enum ReviewSuspension {
    /// Recomputes the cards of the given highlights. Empty ids change nothing. Returns the number of rows changed.
    @discardableResult
    static func recompute(highlightIds: [String], _ db: Database) throws -> Int {
        guard !highlightIds.isEmpty else { return 0 }
        return try recompute(
            condition: "r.highlightId IN (\(placeholders(highlightIds.count)))",
            arguments: bound(highlightIds),
            db
        )
    }

    /// Recomputes the cards of every highlight in the given documents. Empty ids change nothing.
    @discardableResult
    static func recompute(documentIds: [String], _ db: Database) throws -> Int {
        guard !documentIds.isEmpty else { return 0 }
        return try recompute(
            condition: "h.documentId IN (\(placeholders(documentIds.count)))",
            arguments: bound(documentIds),
            db
        )
    }

    /// Recomputes the cards of every document in the category. Returns the number of rows changed.
    @discardableResult
    static func recompute(categoryId: String, _ db: Database) throws -> Int {
        try recompute(condition: "d.categoryId = ?", arguments: bound([categoryId]), db)
    }

    /// One query for every scope: the cards, their category frequency and whether their highlight has a
    /// cloze or qa card. Each row whose stored values differ from the rule is updated on those two columns only.
    private static func recompute(
        condition: String,
        arguments: [(any DatabaseValueConvertible)?],
        _ db: Database
    ) throws -> Int {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT r.*, c.frequency AS categoryFrequency,
                       EXISTS (SELECT 1 FROM reviewCard m
                               WHERE m.highlightId = r.highlightId AND m.cardType IN ('cloze', 'qa')) AS hasMastery
                FROM reviewCard r
                JOIN highlight h ON h.id = r.highlightId
                JOIN document d ON d.id = h.documentId
                JOIN category c ON c.id = d.categoryId
                WHERE \(condition)
                """,
            arguments: StatementArguments(arguments)
        )
        var changed = 0
        for row in rows {
            var card = try ReviewCard(row: row)
            let hasMastery: Bool = row["hasMastery"]
            let categoryFrequency: ReviewFrequency = row["categoryFrequency"]
            let reason = FrequencyPolicy.suspendedReason(
                cardType: card.cardType,
                highlightHasMasteryCards: hasMastery,
                override: card.frequencyOverride,
                category: categoryFrequency
            )
            let suspended = reason != nil
            guard card.suspended != suspended || card.suspendedReason != reason else { continue }
            card.suspended = suspended
            card.suspendedReason = reason
            try card.update(db, columns: ["suspended", "suspendedReason"])
            changed += 1
        }
        return changed
    }

    private static func bound(_ values: [String]) -> [(any DatabaseValueConvertible)?] {
        values.map { $0 as (any DatabaseValueConvertible)? }
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
