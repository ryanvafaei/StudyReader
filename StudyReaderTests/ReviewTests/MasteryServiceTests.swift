import Foundation
import Testing
@testable import StudyReader

/// Mastery card writes from editor drafts (T115, SPEC F-16, ADR-0021).
@Suite("MasteryService")
struct MasteryServiceTests {
    private let base = ReviewTestFixture.base
    private let sourceText = "ATP stores energy for cells"

    private func newCloze(_ ranges: [ClozeRange]) -> MasteryDraft {
        MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .cloze(ranges: ranges))
    }

    private func newQA(_ question: String, _ answer: String) -> MasteryDraft {
        MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: question, answer: answer))
    }

    /// An image highlight in a Normal category (its passive card is not needed by these tests).
    private func seedImageHighlight(_ env: AppEnvironment) async throws -> Highlight {
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
        return highlight
    }

    private func cards(_ env: AppEnvironment, _ highlightId: String) async throws -> [ReviewCard] {
        try await env.reviewCardRepository.cards(forHighlight: highlightId)
    }

    @Test func createsClozeAndQA() async throws {
        let time = base.addingTimeInterval(5 * 3_600)
        let clock = FixedNow(time)
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)

        try await env.masteryService.save(
            [newCloze([ClozeRange(location: 0, length: 3)]), newQA("What?", "Energy")],
            highlightId: highlight.id
        )

        let stored = try await cards(env, highlight.id)
        let cloze = try #require(stored.first { $0.cardType == .cloze })
        let qa = try #require(stored.first { $0.cardType == .qa })
        #expect(stored.count == 3)
        #expect(cloze.state == .new)
        #expect(qa.state == .new)
        #expect(cloze.dueAt == time.storageRounded)
        #expect(qa.dueAt == time.storageRounded)
        #expect(cloze.answer == sourceText)
        #expect(cloze.clozeRanges == [[0, 3]])
        #expect(qa.question == "What?")
        #expect(qa.answer == "Energy")

        let drafts = try await env.masteryService.drafts(highlightId: highlight.id)
        #expect(drafts.count == 2)
        let allSaved = drafts.allSatisfy { $0.isSaved }
        #expect(allSaved)
        #expect(drafts.contains(MasteryDraft(
            id: cloze.id, isSaved: true, kind: .cloze(ranges: [ClozeRange(location: 0, length: 3)])
        )))
        #expect(drafts.contains(MasteryDraft(id: qa.id, isSaved: true, kind: .qa(question: "What?", answer: "Energy"))))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func suspendsPassive() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, passive) = try await ReviewTestFixture.seedCard(env, text: sourceText)

        try await env.masteryService.save(
            [newCloze([ClozeRange(location: 0, length: 3)]), newQA("What?", "Energy")],
            highlightId: highlight.id
        )
        let suspended = try #require(try await env.reviewCardRepository.fetch(id: passive.id))
        #expect(suspended.suspended == true)
        #expect(suspended.suspendedReason == .mastery)

        try await env.masteryService.save([], highlightId: highlight.id)
        let remaining = try await cards(env, highlight.id)
        #expect(remaining.map(\.id) == [passive.id])
        let restored = try #require(try await env.reviewCardRepository.fetch(id: passive.id))
        #expect(restored.suspended == false)
        #expect(restored.suspendedReason == nil)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func reviewedWithHiddenAnswers() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        try await env.masteryService.save(
            [newCloze([ClozeRange(location: 0, length: 3)]), newQA("What?", "Energy")],
            highlightId: highlight.id
        )
        let stored = try await cards(env, highlight.id)
        let cloze = try #require(stored.first { $0.cardType == .cloze })
        let qa = try #require(stored.first { $0.cardType == .qa })

        let items = try await ReviewTestFixture.service(env, clock: clock).items(cardIds: [cloze.id, qa.id])
        let clozeItem = try #require(items.first { $0.card.id == cloze.id })
        let qaItem = try #require(items.first { $0.card.id == qa.id })

        let clozeContent = ReviewCardContent.make(clozeItem)
        #expect(clozeContent.needsReveal)
        guard case .markdown(let front) = clozeContent.front, case .markdown(let back) = clozeContent.back else {
            Issue.record("cloze card should show Markdown on both sides")
            return
        }
        #expect(!front.contains("ATP"))
        #expect(back.contains("**ATP**"))

        let qaContent = ReviewCardContent.make(qaItem)
        #expect(qaContent.needsReveal)
        #expect(qaContent.front == .markdown(RichTextMarkdown.escape("What?")))
        #expect(qaContent.back == .markdown(RichTextMarkdown.escape("Energy")))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func scheduledIndependently() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, passive) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        try await env.masteryService.save(
            [newCloze([ClozeRange(location: 0, length: 3)]), newQA("What?", "Energy")],
            highlightId: highlight.id
        )
        let stored = try await cards(env, highlight.id)
        let cloze = try #require(stored.first { $0.cardType == .cloze })
        let qa = try #require(stored.first { $0.cardType == .qa })
        let service = ReviewTestFixture.service(env, clock: clock)

        let plan = try await service.dailyPlan(limits: .defaults)
        #expect(plan.newCount == 2)
        #expect(plan.dueCount == 0)
        #expect(Set(plan.cardIds) == Set([cloze.id, qa.id]))
        #expect(!plan.cardIds.contains(passive.id))

        let qaBefore = try #require(try await env.reviewCardRepository.fetch(id: qa.id))
        let clozeBefore = try #require(try await env.reviewCardRepository.fetch(id: cloze.id))
        _ = try await service.rate(cardId: cloze.id, rating: .good, context: .daily)

        let clozeAfter = try #require(try await env.reviewCardRepository.fetch(id: cloze.id))
        let qaAfter = try #require(try await env.reviewCardRepository.fetch(id: qa.id))
        #expect(clozeAfter.fsrsCard != clozeBefore.fsrsCard)
        #expect(clozeAfter.dueAt != clozeBefore.dueAt)
        #expect(qaAfter.fsrsCard == qaBefore.fsrsCard)
        #expect(qaAfter.dueAt == qaBefore.dueAt)
        #expect(qaAfter.state == qaBefore.state)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func editKeepsScheduleAndText() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)
        try await env.masteryService.save([newCloze([ClozeRange(location: 0, length: 3)])], highlightId: highlight.id)
        let cloze = try #require(try await cards(env, highlight.id).first { $0.cardType == .cloze })

        _ = try await ReviewTestFixture.service(env, clock: clock).rate(cardId: cloze.id, rating: .good, context: .daily)
        let before = try #require(try await env.reviewCardRepository.fetch(id: cloze.id))

        try await env.highlightRepository.updateEditedText(
            id: highlight.id,
            editedText: "Edited ATP text",
            at: TestData.referenceDate
        )

        try await env.masteryService.save(
            [MasteryDraft(
                id: cloze.id,
                isSaved: true,
                kind: .cloze(ranges: [ClozeRange(location: 0, length: 3), ClozeRange(location: 11, length: 6)])
            )],
            highlightId: highlight.id
        )

        let after = try #require(try await env.reviewCardRepository.fetch(id: cloze.id))
        #expect(after.clozeRanges == [[0, 3], [11, 6]])
        #expect(after.answer == sourceText)
        #expect(after.fsrsCard == before.fsrsCard)
        #expect(after.dueAt == before.dueAt)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func validation() async throws {
        enum Target { case text, image, missing }
        struct Row {
            let name: String
            let target: Target
            let drafts: [MasteryDraft]
            let error: MasteryError
        }
        let rows: [Row] = [
            Row(name: "cloze without ranges", target: .text,
                drafts: [MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .cloze(ranges: []))],
                error: .emptyCloze),
            Row(name: "cloze with only invalid ranges", target: .text,
                drafts: [MasteryDraft(id: UUID().uuidString, isSaved: false,
                                      kind: .cloze(ranges: [ClozeRange(location: 40, length: 3)]))],
                error: .emptyCloze),
            Row(name: "qa with blank question", target: .text,
                drafts: [MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "  ", answer: "Energy"))],
                error: .emptyQuestion),
            Row(name: "qa with empty answer", target: .text,
                drafts: [MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "What?", answer: ""))],
                error: .emptyAnswer),
            Row(name: "valid qa with an invalid cloze", target: .text,
                drafts: [
                    MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "What?", answer: "Energy")),
                    MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .cloze(ranges: [])),
                ],
                error: .emptyCloze),
            Row(name: "cloze on an image highlight", target: .image,
                drafts: [MasteryDraft(id: UUID().uuidString, isSaved: false,
                                      kind: .cloze(ranges: [ClozeRange(location: 0, length: 3)]))],
                error: .clozeOnImage),
            Row(name: "deleted highlight", target: .missing,
                drafts: [MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "What?", answer: "Energy"))],
                error: .highlightMissing),
        ]

        for row in rows {
            let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
            let env = try AppEnvironment.inMemory(now: clock)
            let highlightId: String
            switch row.target {
            case .text:
                highlightId = try await ReviewTestFixture.seedCard(env, text: sourceText).highlight.id
            case .image:
                highlightId = try await seedImageHighlight(env).id
            case .missing:
                highlightId = "missing-highlight"
            }
            if row.target != .missing {
                // A saved Q&A card that a failing save must leave untouched.
                try await env.masteryService.save([newQA("Existing?", "Existing")], highlightId: highlightId)
            }
            let before = try await cards(env, highlightId)

            do {
                try await env.masteryService.save(row.drafts, highlightId: highlightId)
                Issue.record("\(row.name): expected \(row.error)")
            } catch let error as MasteryError {
                #expect(error == row.error, "\(row.name)")
            } catch {
                Issue.record("\(row.name): unexpected error \(error)")
            }

            #expect(try await cards(env, highlightId) == before, "\(row.name): cards changed")
            try await env.database.writer.write { db in try FTSIntegrity.check(db) }
        }
    }

    @Test func sourceText() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (highlight, _) = try await ReviewTestFixture.seedCard(env, text: sourceText)

        #expect(try await env.masteryService.clozeSourceText(highlightId: highlight.id) == sourceText)

        try await env.highlightRepository.updateEditedText(
            id: highlight.id,
            editedText: "Edited ATP",
            at: TestData.referenceDate
        )
        #expect(try await env.masteryService.clozeSourceText(highlightId: highlight.id) == "Edited ATP")

        let image = try await seedImageHighlight(env)
        #expect(try await env.masteryService.clozeSourceText(highlightId: image.id) == "")

        await #expect(throws: MasteryError.highlightMissing) {
            _ = try await env.masteryService.clozeSourceText(highlightId: "missing-highlight")
        }

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
