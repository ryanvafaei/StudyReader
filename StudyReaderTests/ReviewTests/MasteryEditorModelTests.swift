import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("MasteryEditorModel")
struct MasteryEditorModelTests {
    private let base = ReviewTestFixture.base
    private let sourceText = "ATP stores energy for cells and more text"

    private func makeEnv() throws -> AppEnvironment {
        try AppEnvironment.inMemory(now: FixedNow(base.addingTimeInterval(5 * 3_600)))
    }

    @Test func loadReadsTextAndDrafts() async throws {
        let env = try makeEnv()
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        try await env.masteryService.save(
            [MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "What?", answer: "Energy"))],
            highlightId: highlight.id
        )
        let model = MasteryEditorModel(highlightId: highlight.id, environment: env)
        #expect(!model.hasLoaded)
        await model.load()
        #expect(model.hasLoaded)
        #expect(model.sourceText == sourceText)
        #expect(model.drafts.count == 1)
        #expect(model.drafts.first?.isSaved == true)
        #expect(!model.isDirty)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func addClozeFromSelection() async throws {
        let env = try makeEnv()
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        let model = MasteryEditorModel(highlightId: highlight.id, environment: env)
        await model.load()

        model.selection = ClozeRange(location: 4, length: 0)
        #expect(!model.canAddCloze)
        model.addCloze()
        #expect(model.drafts.isEmpty)

        model.selection = ClozeRange(location: 4, length: 12)
        #expect(model.canAddCloze)
        model.addCloze()
        #expect(model.drafts.count == 1)
        #expect(model.drafts[0].kind == .cloze(ranges: [ClozeRange(location: 4, length: 12)]))
        #expect(model.selectedDraftId == model.drafts[0].id)
        #expect(model.selection == nil)
        #expect(model.isDirty)

        model.selection = ClozeRange(location: 20, length: 3)
        model.addSelectionToSelectedCloze()
        #expect(model.drafts[0].kind == .cloze(ranges: [
            ClozeRange(location: 4, length: 12),
            ClozeRange(location: 20, length: 3),
        ]))
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func addQuestionDefaultsAnswer() async throws {
        let env = try makeEnv()
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        let model = MasteryEditorModel(highlightId: highlight.id, environment: env)
        await model.load()

        model.addQuestion()
        model.addQuestion()
        let first = model.drafts[0].id
        let second = model.drafts[1].id
        #expect(model.drafts[0].kind == .qa(question: "", answer: sourceText))
        #expect(model.selectedDraftId == second)

        model.updateQuestion("Q1", for: first)
        model.updateAnswer("A1", for: first)
        #expect(model.drafts[0].kind == .qa(question: "Q1", answer: "A1"))
        #expect(model.drafts[1].kind == .qa(question: "", answer: sourceText))
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func saveAppliesAndReportsErrors() async throws {
        let env = try makeEnv()
        let (highlight, passive) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        let model = MasteryEditorModel(highlightId: highlight.id, environment: env)
        await model.load()

        model.addQuestion()
        let id = model.drafts[0].id
        #expect(await model.save() == false)
        #expect(model.errorMessage == "Write a question.")
        #expect(try await env.reviewCardRepository.cards(forHighlight: highlight.id).count == 1)

        model.updateQuestion("What?", for: id)
        #expect(await model.save() == true)
        let cards = try await env.reviewCardRepository.cards(forHighlight: highlight.id)
        #expect(cards.contains { $0.cardType == .qa && $0.question == "What?" })
        let suspended = try #require(try await env.reviewCardRepository.fetch(id: passive.id))
        #expect(suspended.suspended == true)

        let reopened = MasteryEditorModel(highlightId: highlight.id, environment: env)
        await reopened.load()
        #expect(reopened.drafts.count == 1)
        reopened.remove(reopened.drafts[0].id)
        #expect(await reopened.save() == true)
        #expect(try await env.reviewCardRepository.cards(forHighlight: highlight.id).allSatisfy { $0.cardType == .passive })
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func imageHighlightHasNoCloze() async throws {
        let env = try makeEnv()
        try await env.categoryRepository.setFrequency(id: BuiltinCategory.lectureSlides.id, .normal)
        let document = TestData.document()
        try await env.documentRepository.insert(document)
        let highlight = Highlight(
            id: UUID().uuidString,
            documentId: document.id,
            kind: .image,
            view: .pdf,
            color: .green,
            pageIndex: 7,
            positionKey: 7.1,
            anchor: .image(ImageAnchor(pageIndex: 7, rect: CGRectCodable(x: 10, y: 20, width: 200, height: 150))),
            imagePath: "\(document.id)/highlights/b2.png",
            createdAt: TestData.referenceDate,
            updatedAt: TestData.referenceDate
        )
        try await env.highlightRepository.insert(highlight)

        let model = MasteryEditorModel(highlightId: highlight.id, environment: env)
        await model.load()
        model.selection = ClozeRange(location: 0, length: 3)
        #expect(model.isImageHighlight)
        #expect(!model.canAddCloze)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
