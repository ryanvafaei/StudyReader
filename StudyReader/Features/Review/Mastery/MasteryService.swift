import Foundation

/// One Mastery card in the editor's list (SPEC F-16, ADR-0021). `id` is the card's id when `isSaved` is true,
/// otherwise a new id that `save` ignores.
struct MasteryDraft: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        case cloze(ranges: [ClozeRange])
        case qa(question: String, answer: String)
    }
    var id: String
    var isSaved: Bool
    var kind: Kind
}

enum MasteryError: Error, Equatable, LocalizedError {
    case highlightMissing
    case emptyCloze
    case emptyQuestion
    case emptyAnswer
    case clozeOnImage

    var errorDescription: String? {
        switch self {
        case .highlightMissing: "This highlight no longer exists."
        case .emptyCloze: "Select at least one word to hide."
        case .emptyQuestion: "Write a question."
        case .emptyAnswer: "Write an answer."
        case .clozeOnImage: "Image highlights can't have cloze cards."
        }
    }
}

/// Creates, changes and deletes a highlight's Mastery cards (cloze and Q&A) from the editor's drafts (T115,
/// SPEC F-16, ADR-0021). Every draft is validated before anything is written. Writes run inserts, then updates,
/// then deletes, each through `ReviewCardRepository`, so the passive card is never restored while cards are replaced.
actor MasteryService {
    private let cards: ReviewCardRepository
    private let highlights: HighlightRepository
    private let now: any Now

    init(cards: ReviewCardRepository, highlights: HighlightRepository, now: any Now) {
        self.cards = cards
        self.highlights = highlights
        self.now = now
    }

    /// editedText ?? text for a text highlight; "" for an image highlight. Missing → `.highlightMissing`.
    func clozeSourceText(highlightId: String) async throws -> String {
        guard let highlight = try await highlights.fetch(id: highlightId) else {
            throw MasteryError.highlightMissing
        }
        return Self.sourceText(of: highlight)
    }

    /// The highlight's cloze and Q&A cards as saved drafts, in `cards(forHighlight:)` order. A cloze's ranges are
    /// normalized against its stored `answer`, which holds the text it was made from (ADR-0021).
    func drafts(highlightId: String) async throws -> [MasteryDraft] {
        try await cards.cards(forHighlight: highlightId).compactMap { card in
            switch card.cardType {
            case .passive:
                return nil
            case .cloze:
                let ranges = ClozeText.normalized(card.clozeRanges ?? [], in: card.answer ?? "")
                return MasteryDraft(id: card.id, isSaved: true, kind: .cloze(ranges: ranges))
            case .qa:
                return MasteryDraft(
                    id: card.id,
                    isSaved: true,
                    kind: .qa(question: card.question ?? "", answer: card.answer ?? "")
                )
            }
        }
    }

    /// Applies the editor's list to the highlight's Mastery cards.
    /// - Every draft is validated first; nothing is written if one fails.
    /// - An unsaved draft (or a saved one that matches no cloze/Q&A card of this highlight) becomes a new card with a
    ///   fresh FSRS state. A cloze stores the current source text in `answer`.
    /// - A saved draft whose content changed is updated. A cloze keeps its stored text in `answer`, and its ranges
    ///   are validated against that text.
    /// - Saved cards of this highlight that are not kept are deleted.
    func save(_ drafts: [MasteryDraft], highlightId: String) async throws {
        let moment = now()
        guard let highlight = try await highlights.fetch(id: highlightId) else {
            throw MasteryError.highlightMissing
        }
        let existing = try await cards.cards(forHighlight: highlightId).filter { $0.cardType != .passive }
        let sourceText = Self.sourceText(of: highlight)
        let isImage = highlight.kind == .image

        func match(_ draft: MasteryDraft, type: CardType) -> ReviewCard? {
            guard draft.isSaved else { return nil }
            return existing.first { $0.id == draft.id && $0.cardType == type }
        }

        var inserts: [ReviewCard] = []
        var updates: [PendingUpdate] = []
        var keptIds: Set<String> = []

        // Validation pass: builds every write and throws before any write happens.
        for draft in drafts {
            switch draft.kind {
            case .cloze(let ranges):
                if isImage {
                    throw MasteryError.clozeOnImage
                }
                let stored = match(draft, type: .cloze)
                let baseText = stored.map { $0.answer ?? "" } ?? sourceText
                let normalized = ClozeText.normalized(ranges.map(\.pair), in: baseText)
                guard !normalized.isEmpty else {
                    throw MasteryError.emptyCloze
                }
                if let stored {
                    keptIds.insert(stored.id)
                    let storedRanges = ClozeText.normalized(stored.clozeRanges ?? [], in: baseText)
                    if storedRanges != normalized {
                        updates.append(PendingUpdate(
                            id: stored.id,
                            clozeRanges: normalized.map(\.pair),
                            question: nil,
                            answer: stored.answer
                        ))
                    }
                } else {
                    inserts.append(try ReviewCardFactory.mastery(
                        highlightId: highlightId,
                        cardType: .cloze,
                        clozeRanges: normalized.map(\.pair),
                        question: nil,
                        answer: sourceText,
                        now: moment
                    ))
                }

            case .qa(let question, let answer):
                let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedQuestion.isEmpty else {
                    throw MasteryError.emptyQuestion
                }
                guard !trimmedAnswer.isEmpty else {
                    throw MasteryError.emptyAnswer
                }
                if let stored = match(draft, type: .qa) {
                    keptIds.insert(stored.id)
                    if stored.question != trimmedQuestion || stored.answer != trimmedAnswer {
                        updates.append(PendingUpdate(
                            id: stored.id,
                            clozeRanges: nil,
                            question: trimmedQuestion,
                            answer: trimmedAnswer
                        ))
                    }
                } else {
                    inserts.append(try ReviewCardFactory.mastery(
                        highlightId: highlightId,
                        cardType: .qa,
                        clozeRanges: nil,
                        question: trimmedQuestion,
                        answer: trimmedAnswer,
                        now: moment
                    ))
                }
            }
        }
        let deletedIds = existing.map(\.id).filter { !keptIds.contains($0) }

        // Write pass: inserts, then updates, then deletes. Each repository call is one transaction.
        if !inserts.isEmpty {
            do {
                try await cards.insertMasteryCards(inserts, highlightId: highlightId)
            } catch RepositoryError.notFound {
                // The highlight was deleted after it was read above.
                throw MasteryError.highlightMissing
            }
        }
        for update in updates {
            try await cards.updateMasteryCard(
                id: update.id,
                clozeRanges: update.clozeRanges,
                question: update.question,
                answer: update.answer
            )
        }
        for id in deletedIds {
            try await cards.deleteMasteryCard(id: id)
        }
    }

    /// A stored card's new column values (`updateMasteryCard`).
    private struct PendingUpdate {
        var id: String
        var clozeRanges: [[Int]]?
        var question: String?
        var answer: String?
    }

    /// The text a cloze is made from: editedText ?? text, or "" for an image highlight.
    private static func sourceText(of highlight: Highlight) -> String {
        highlight.kind == .image ? "" : (highlight.editedText ?? highlight.text)
    }
}
