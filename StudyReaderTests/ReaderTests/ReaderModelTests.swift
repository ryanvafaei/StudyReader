import Foundation
import GRDB
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
    func failedLoadHidesThePanelAndIgnoresToggle() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        model.navigate(to: .documentNote)
        #expect(model.isRightPanelVisible)
        await model.load()

        #expect(model.isDocumentAvailable == false)
        #expect(model.isRightPanelVisible == false)
        model.toggleRightPanel(tab: .highlights)
        #expect(model.isRightPanelVisible == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func engineFailedMarksTheDocumentUnavailable() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()
        #expect(model.isDocumentAvailable)
        model.toggleRightPanel(tab: .highlights)
        #expect(model.isRightPanelVisible)

        model.engineFailed("x")

        #expect(model.state == .failed("x"))
        #expect(model.isDocumentAvailable == false)
        #expect(model.isRightPanelVisible == false)
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
        #expect(model.canUndoHighlight)

        await model.undoLastAutoHighlight()
        #expect(!model.canUndoHighlight)
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
        #expect(!model.canUndoHighlight)

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

    /// A model observing a document's highlights, holding one auto-highlight that ⌘Z could undo.
    private static func modelWithAutoHighlight(
        _ session: AppSession
    ) async throws -> (model: ReaderModel, observer: Task<Void, Never>, highlight: Highlight) {
        try await ReaderTestSupport.insertDocument(session, id: documentId, withFile: false)
        let model = ReaderModel(documentId: documentId, session: session)
        let observer = Task { await model.observeHighlights() }
        let highlight = try #require(await model.createHighlight(
            ReaderTestSupport.selection(documentId: documentId),
            isAuto: true
        ))
        #expect(model.canUndoHighlight)
        let listed = await ReaderTestSupport.waitUntil { model.highlights.count == 1 }
        #expect(listed)
        #expect(model.canUndoHighlight)
        return (model, observer, highlight)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoIsClearedWhenThePopoverRecolorsTheAutoHighlight() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let (model, observer, highlight) = try await Self.modelWithAutoHighlight(session)
        defer { observer.cancel() }

        await HighlightPopoverModel(highlightId: highlight.id, session: session).setColor(.purple)

        let cleared = await ReaderTestSupport.waitUntil { !model.canUndoHighlight }
        #expect(cleared)
        #expect(model.highlights.first?.color == .purple)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoIsKeptWhenThePopoverPicksTheCurrentColor() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let (model, observer, highlight) = try await Self.modelWithAutoHighlight(session)
        defer { observer.cancel() }
        let popover = HighlightPopoverModel(highlightId: highlight.id, session: session)
        let popoverObserver = Task { await popover.observe() }
        defer { popoverObserver.cancel() }
        let loaded = await ReaderTestSupport.waitUntil { popover.highlight != nil }
        #expect(loaded)

        await popover.setColor(highlight.color)

        #expect(model.canUndoHighlight)
        await model.undoLastAutoHighlight()
        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoIsClearedWhenThePopoverDeletesTheAutoHighlight() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let (model, observer, highlight) = try await Self.modelWithAutoHighlight(session)
        defer { observer.cancel() }

        await HighlightPopoverModel(highlightId: highlight.id, session: session).delete()

        let cleared = await ReaderTestSupport.waitUntil { !model.canUndoHighlight }
        #expect(cleared)
        #expect(model.highlights.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoIsClearedWhenThePanelDeletesTheAutoHighlight() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let (model, observer, highlight) = try await Self.modelWithAutoHighlight(session)
        defer { observer.cancel() }

        await HighlightsPanelModel(model: model).delete(highlight.id)

        let cleared = await ReaderTestSupport.waitUntil { !model.canUndoHighlight }
        #expect(cleared)
        #expect(model.highlights.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoIsClearedByAPanelDeleteWhenTheSnapshotLandedBeforeTheMarkWasSet() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        let model = ReaderModel(documentId: Self.documentId, session: session)
        let observer = Task { await model.observeHighlights() }
        defer { observer.cancel() }

        let highlight = try await session.environment.highlightService.createText(
            ReaderTestSupport.selection(documentId: Self.documentId),
            isAuto: true
        )
        let listed = await ReaderTestSupport.waitUntil { model.highlights.count == 1 }
        #expect(listed)

        model.rememberAutoHighlight(highlight)
        #expect(model.canUndoHighlight)

        await HighlightsPanelModel(model: model).delete(highlight.id)

        let cleared = await ReaderTestSupport.waitUntil { !model.canUndoHighlight }
        #expect(cleared)
        #expect(model.highlights.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoInOneTabKeepsAnotherTabsAutoHighlight() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let otherDocumentId = "30000000-0000-0000-0000-0000000000E2"
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        try await ReaderTestSupport.insertDocument(session, id: otherDocumentId, withFile: false)
        let modelA = ReaderModel(documentId: Self.documentId, session: session)
        let modelB = ReaderModel(documentId: otherDocumentId, session: session)

        let a = await modelA.createHighlight(ReaderTestSupport.selection(documentId: Self.documentId), isAuto: true)
        let b = await modelB.createHighlight(ReaderTestSupport.selection(documentId: otherDocumentId), isAuto: true)
        #expect(a != nil)
        #expect(b != nil)

        await modelA.undoLastAutoHighlight()

        #expect(!modelA.canUndoHighlight)
        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 1)
        #expect(await ReaderTestSupport.highlightCount(session, documentId: otherDocumentId) == 1)

        await modelB.undoLastAutoHighlight()
        #expect(await ReaderTestSupport.highlightCount(session, documentId: otherDocumentId) == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func undoIsClearedWhenAnotherHighlightFailsToSave() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let (model, observer, _) = try await Self.modelWithAutoHighlight(session)
        defer { observer.cancel() }

        let failed = await model.createHighlight(
            ReaderTestSupport.selection(documentId: Self.documentId, text: "   "),
            isAuto: false
        )

        #expect(failed == nil)
        #expect(!model.canUndoHighlight)
        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionFinishedReturnsTheHighlight() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        let model = ReaderModel(documentId: Self.documentId, session: session)
        let new = ReaderTestSupport.selection(documentId: Self.documentId)

        session.settings.autoHighlight = true
        session.settings.currentColor = .green
        let created = await model.selectionFinished(new, anchorRect: Self.anchorRect)
        #expect(created?.color == .green)
        #expect(created?.documentId == Self.documentId)
        #expect(model.canUndoHighlight)

        session.settings.autoHighlight = false
        let none = await model.selectionFinished(new, anchorRect: Self.anchorRect)
        #expect(none == nil)
        #expect(model.selectionToolbar != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionFinishedReturnsNilOnFailure() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        session.settings.autoHighlight = true
        let model = ReaderModel(documentId: Self.documentId, session: session)

        let result = await model.selectionFinished(
            ReaderTestSupport.selection(documentId: Self.documentId, text: "   "),
            anchorRect: Self.anchorRect
        )

        #expect(result == nil)
        #expect(model.transientMessage != nil)
        #expect(!model.canUndoHighlight)
    }

    @Test(.timeLimit(.minutes(1)))
    func hasLoadedHighlightsAfterFirstEmission() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: false)
        let model = ReaderModel(documentId: Self.documentId, session: session)
        #expect(!model.hasLoadedHighlights)

        let observer = Task { await model.observeHighlights() }
        defer { observer.cancel() }

        let loaded = await ReaderTestSupport.waitUntil { model.hasLoadedHighlights }
        #expect(loaded)
        #expect(model.highlights.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedUndoKeepsTheMark() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let (model, observer, _) = try await Self.modelWithAutoHighlight(session)
        defer { observer.cancel() }
        try await session.environment.database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER blockHighlightDelete BEFORE DELETE ON highlight
                BEGIN SELECT RAISE(ABORT, 'blocked'); END
                """)
        }

        await model.undoLastAutoHighlight()

        #expect(model.canUndoHighlight)
        #expect(model.transientMessage != nil)
        #expect(await ReaderTestSupport.highlightCount(session, documentId: Self.documentId) == 1)

        try await session.environment.database.writer.write { db in
            try db.execute(sql: "DROP TRIGGER blockHighlightDelete")
        }
        await model.undoLastAutoHighlight()
        #expect(!model.canUndoHighlight)
        #expect(model.transientMessage == nil)
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
