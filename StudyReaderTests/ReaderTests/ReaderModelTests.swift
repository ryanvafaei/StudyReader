import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ReaderModel")
struct ReaderModelTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000E1"
    private static let anchorRect = CGRect(x: 10, y: 20, width: 100, height: 14)

    @Test(.timeLimit(.minutes(1)))
    func missingDocumentFails() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()

        #expect(model.state == .failed("This document is no longer in the library."))
        #expect(model.fileURL == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func missingFileFails() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()

        #expect(model.state == .failed("The document file is missing."))
        #expect(model.fileURL == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func missingFileKeepsDocumentTitle() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()

        #expect(model.state == .failed("The document file is missing."))
        #expect(model.fileURL == nil)
        #expect(model.document?.title == TestData.document(id: Self.documentId).title)
        #expect(model.categoryName != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func subtitleFollowsCategoryRenameAndDelete() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        let environment = session.environment
        let category = try await environment.categoryRepository.create(name: "Biology")
        let original = try #require(await ReaderTestSupport.row(session, id: Self.documentId))
        try await environment.documentRepository.updateMetadata(
            id: Self.documentId,
            title: original.title,
            author: original.author,
            categoryId: category.id
        )

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()
        #expect(model.categoryName == "Biology")

        let observer = Task { await model.observeMetadata() }
        defer { observer.cancel() }

        try await environment.categoryRepository.rename(id: category.id, to: "Cell Biology")
        let renamed = await ReaderTestSupport.waitUntil { model.categoryName == "Cell Biology" }
        #expect(renamed)

        try await environment.categoryRepository.delete(id: category.id)
        let moved = await ReaderTestSupport.waitUntil { model.categoryName == "Other" }
        #expect(moved)
        #expect(model.document?.categoryId == BuiltinCategory.other.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func autoHighlightCreatesImmediately() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        session.settings.autoHighlight = true
        session.settings.currentColor = .blue

        let model = ReaderModel(documentId: Self.documentId, session: session)
        let new = ReaderTestSupport.selection(documentId: Self.documentId)
        await model.selectionFinished(new, anchorRect: Self.anchorRect)

        #expect(model.selectionToolbar == nil)
        let rows = try await session.environment.highlightRepository.fetchForDocument(Self.documentId)
        #expect(rows.count == 1)
        #expect(rows.first?.color == .blue)

        await model.undoLastAutoHighlight()
        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func toolbarWhenAutoHighlightOff() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        session.settings.autoHighlight = false
        session.settings.currentColor = .green

        let model = ReaderModel(documentId: Self.documentId, session: session)
        let new = ReaderTestSupport.selection(documentId: Self.documentId, color: .green)
        await model.selectionFinished(new, anchorRect: Self.anchorRect)

        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 0)
        #expect(model.selectionToolbar?.pending == new)

        await model.applyToolbarColor(.pink)
        #expect(model.selectionToolbar == nil)
        let rows = try await session.environment.highlightRepository.fetchForDocument(Self.documentId)
        #expect(rows.count == 1)
        #expect(rows.first?.color == .pink)

        await model.selectionFinished(new, anchorRect: Self.anchorRect)
        await model.applyToolbarNoteOrTag(focus: .note)
        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 2)
        #expect(model.popoverRequest?.focus == .note)
        #expect(model.selectionToolbar == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func highlightsAreLive() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        let observer = Task { await model.observeHighlights() }
        defer { observer.cancel() }

        let created = await model.createHighlight(
            ReaderTestSupport.selection(documentId: Self.documentId),
            isAuto: false
        )
        #expect(created != nil)

        let live = await ReaderTestSupport.waitUntil { model.highlights.count == 1 }
        #expect(live)
    }

    @Test
    func documentNoteLocationOpensNotesTab() throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }

        let model = ReaderModel(documentId: Self.documentId, session: session)
        model.navigate(to: .documentNote)

        #expect(model.isRightPanelVisible)
        #expect(model.rightPanelTab == .notes)
        #expect(model.pendingLocation == .documentNote)

        model.consumeLocation()
        #expect(model.pendingLocation == nil)
    }
}
