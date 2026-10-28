import Foundation
import Testing
@testable import StudyReader

@Suite("HighlightsPanelModel")
struct HighlightsPanelModelTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000F1"

    private static func make(
        id: String,
        view: ReaderViewKind,
        key: Double,
        createdAt: Date = TestData.referenceDate
    ) -> Highlight {
        var highlight = TestData.highlight(documentId: documentId, id: id, positionKey: key, createdAt: createdAt)
        highlight.view = view
        return highlight
    }

    @Test
    func sectionsForPDFDocument() {
        let highlights = [
            Self.make(id: "a", view: .pdf, key: 2_000_100),
            Self.make(id: "b", view: .text, key: 5),
            Self.make(id: "c", view: .pdf, key: 100)
        ]
        let sections = HighlightsPanelModel.sections(for: highlights, tagNames: [:], fileType: .pdf)

        #expect(sections.map(\.title) == ["PDF view", "Text view"])
        #expect(sections[0].rows.map(\.id) == ["c", "a"])
        #expect(sections[0].rows.allSatisfy { $0.viewLabel == "PDF" })
        #expect(sections[1].rows.map(\.id) == ["b"])
        #expect(sections[1].rows[0].viewLabel == "Text")
    }

    @Test
    func singleSectionForPDFWithOneKind() {
        let sections = HighlightsPanelModel.sections(
            for: [Self.make(id: "a", view: .pdf, key: 1)], tagNames: [:], fileType: .pdf
        )
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].rows[0].viewLabel == "PDF")
    }

    @Test
    func singleSectionForMarkdown() {
        let early = TestData.referenceDate
        let highlights = [
            Self.make(id: "a", view: .markdown, key: 50),
            Self.make(id: "b", view: .markdown, key: 10),
            Self.make(id: "c", view: .markdown, key: 10, createdAt: early.addingTimeInterval(-60))
        ]
        let sections = HighlightsPanelModel.sections(for: highlights, tagNames: [:], fileType: .markdown)

        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].rows.map(\.id) == ["c", "b", "a"])
        #expect(sections[0].rows.allSatisfy { $0.viewLabel == nil })
    }

    @Test
    func orphansAreListed() {
        var orphan = Self.make(id: "o", view: .markdown, key: 1)
        orphan.anchorStatus = .orphaned
        let sections = HighlightsPanelModel.sections(
            for: [orphan, Self.make(id: "k", view: .markdown, key: 2)], tagNames: [:], fileType: .markdown
        )
        let rows = sections.flatMap(\.rows)

        #expect(rows.map(\.id) == ["o", "k"])
        #expect(rows[0].isOrphaned)
        #expect(!rows[1].isOrphaned)
    }

    @Test
    func tagsAttached() {
        let highlights = [
            Self.make(id: "a", view: .markdown, key: 1),
            Self.make(id: "b", view: .markdown, key: 2)
        ]
        let sections = HighlightsPanelModel.sections(
            for: highlights, tagNames: ["a": ["exam", "ch1"]], fileType: .markdown
        )
        let rows = sections[0].rows

        #expect(rows[0].tagNames == ["exam", "ch1"])
        #expect(rows[1].tagNames.isEmpty)
    }

    @Test
    func viewLabelsAreLocalizedStrings() {
        let sections = HighlightsPanelModel.sections(
            for: [Self.make(id: "a", view: .pdf, key: 1), Self.make(id: "b", view: .text, key: 2)],
            tagNames: [:],
            fileType: .pdf
        )
        #expect(sections[0].rows[0].viewLabel == String(localized: "PDF"))
        #expect(sections[1].rows[0].viewLabel == String(localized: "Text"))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func tagChipsFollowTagChanges() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)
        let environment = session.environment
        let highlight = TestData.highlight(documentId: Self.documentId, id: "tagged", positionKey: 1)
        try await environment.highlightRepository.insert(highlight)
        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()
        let highlightsTask = Task { await model.observeHighlights() }
        defer { highlightsTask.cancel() }
        let panel = HighlightsPanelModel(model: model)
        let tagsTask = Task { await panel.observeTagNames() }
        defer { tagsTask.cancel() }

        let listed = await ReaderTestSupport.waitUntil {
            await panel.refresh()
            return panel.sections.flatMap(\.rows).map(\.id) == ["tagged"]
        }
        #expect(listed)
        let highlightsBefore = model.highlights

        let tag = try await environment.tagRepository.findOrCreate(name: "exam", at: TestData.referenceDate)
        try await environment.tagRepository.addTag(tag.id, toHighlights: ["tagged"])
        let tagged = await ReaderTestSupport.waitUntil {
            panel.sections.flatMap(\.rows).first?.tagNames == ["exam"]
        }
        #expect(tagged)
        #expect(model.highlights == highlightsBefore)

        try await environment.tagRepository.rename(id: tag.id, to: "final")
        let renamed = await ReaderTestSupport.waitUntil {
            panel.sections.flatMap(\.rows).first?.tagNames == ["final"]
        }
        #expect(renamed)
    }

    @Test
    func noHighlightsGivesNoSections() {
        #expect(HighlightsPanelModel.sections(for: [], tagNames: [:], fileType: .pdf).isEmpty)
    }
}
