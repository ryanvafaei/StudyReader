import Foundation
import GRDB
import Testing
@testable import StudyReader

/// One row of the category table for new highlights (SPEC F-17 AC1).
struct CardCreationRow: Sendable {
    let name: String
    let categoryId: String
    let frequency: ReviewFrequency
    let autoCreateCards: Bool
    let expectedCards: Int
}

/// Passive cards created with a highlight (T100, SPEC F-15, F-17 AC1, ADR-0021).
@Suite("CardCreation")
struct CardCreationTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000C1"

    /// 1×1 transparent PNG, so the snapshot test writes a real image.
    private static let onePixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    static let categoryRows: [CardCreationRow] = [
        CardCreationRow(name: "Lecture slides", categoryId: BuiltinCategory.lectureSlides.id,
                        frequency: .high, autoCreateCards: true, expectedCards: 1),
        CardCreationRow(name: "Notes", categoryId: BuiltinCategory.notes.id,
                        frequency: .normal, autoCreateCards: false, expectedCards: 0),
        CardCreationRow(name: "Paper", categoryId: BuiltinCategory.paper.id,
                        frequency: .off, autoCreateCards: true, expectedCards: 0),
        CardCreationRow(name: "Other", categoryId: BuiltinCategory.other.id,
                        frequency: .normal, autoCreateCards: true, expectedCards: 1),
    ]

    private static func textSelection(
        documentId: String = documentId,
        text: String = "Selected text"
    ) -> NewTextHighlight {
        NewTextHighlight(
            documentId: documentId,
            view: .markdown,
            anchor: .text(TextAnchor(
                start: 0,
                length: text.utf16.count,
                text: text,
                prefix: "",
                suffix: "",
                sourceVersion: 1
            )),
            text: text,
            richText: text,
            pageIndex: nil,
            positionKey: 0,
            color: .yellow
        )
    }

    private static func setCategory(
        _ env: AppEnvironment,
        id: String,
        frequency: ReviewFrequency,
        autoCreateCards: Bool
    ) async throws {
        try await env.database.writer.write { db in
            guard var category = try DocumentCategory.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            category.frequency = frequency
            category.autoCreateCards = autoCreateCards
            try category.update(db, columns: ["frequency", "autoCreateCards"])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func respectsCategorySetting() async throws {
        for row in Self.categoryRows {
            let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
            defer { TestFileStore.remove(env.fileStore) }
            let docId = "30000000-0000-0000-0000-0000000000D1"
            try await Self.setCategory(env, id: row.categoryId, frequency: row.frequency,
                                       autoCreateCards: row.autoCreateCards)
            try await env.documentRepository.insert(TestData.document(id: docId, categoryId: row.categoryId))

            let created = try await env.highlightService.createText(
                Self.textSelection(documentId: docId), isAuto: false
            )
            let cards = try await env.reviewCardRepository.cards(forHighlight: created.id)
            #expect(cards.count == row.expectedCards, "\(row.name)")
            if row.expectedCards == 1 {
                #expect(cards.first?.cardType == .passive, "\(row.name)")
                #expect(cards.first?.suspended == false, "\(row.name)")
            }
            try await env.database.writer.write { db in try FTSIntegrity.check(db) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func newCardIsNewAndDueAtCreation() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))

        let created = try await env.highlightService.createText(Self.textSelection(), isAuto: false)
        let cards = try await env.reviewCardRepository.cards(forHighlight: created.id)
        let card = try #require(cards.first)

        #expect(card.state == .new)
        #expect(card.dueAt == created.createdAt)
        #expect(card.introducedAt == nil)
        #expect(try StoredFSRSCard(json: card.fsrsCard) == .new(due: created.createdAt))
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func imageHighlightGetsACard() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let png = try #require(Data(base64Encoded: Self.onePixelPNG))

        let created = try await env.highlightService.createImage(NewImageHighlight(
            documentId: Self.documentId,
            pageIndex: 0,
            rect: CGRectCodable(x: 0, y: 0, width: 1, height: 1),
            positionKey: 0,
            color: .green,
            pngData: png
        ))
        let cards = try await env.reviewCardRepository.cards(forHighlight: created.id)
        #expect(cards.count == 1)
        #expect(cards.first?.cardType == .passive)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func undoRemovesTheCard() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))

        let created = try await env.highlightService.createText(Self.textSelection(), isAuto: true)
        let undone = try await env.highlightService.undoAutoHighlight(id: created.id)
        #expect(undone == created.id)

        let remaining = try await env.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewCard") ?? -1
        }
        #expect(remaining == 0)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
