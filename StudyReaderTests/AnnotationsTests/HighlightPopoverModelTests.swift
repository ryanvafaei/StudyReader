import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("HighlightPopoverModel")
struct HighlightPopoverModelTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000B1"

    private static func makeSession() async throws -> AppSession {
        let session = try ReaderTestSupport.makeSession()
        try await session.environment.documentRepository.insert(TestData.document(id: documentId))
        return session
    }

    @Test(.timeLimit(.minutes(1)))
    func colorAndDelete() async throws {
        let session = try await Self.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let repository = session.environment.highlightRepository
        let highlight = TestData.highlight(documentId: Self.documentId)
        try await repository.insert(highlight)
        let model = HighlightPopoverModel(highlightId: highlight.id, session: session)

        await model.setColor(.purple)
        #expect(try await repository.fetch(id: highlight.id)?.color == .purple)

        await model.delete()
        #expect(try await repository.fetch(id: highlight.id) == nil)
        #expect(model.isDeleted)
        #expect(model.isGone)
    }

    @Test(.timeLimit(.minutes(1)))
    func copyTextPrefersEditedText() async throws {
        let session = try await Self.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let repository = session.environment.highlightRepository
        var edited = TestData.highlight(documentId: Self.documentId, text: "Original")
        edited.editedText = "Edited"
        let plain = TestData.highlight(documentId: Self.documentId, text: "Plain")
        try await repository.insert(edited)
        try await repository.insert(plain)

        for (highlight, expected) in [(edited, "Edited"), (plain, "Plain")] {
            let model = HighlightPopoverModel(highlightId: highlight.id, session: session)
            let task = Task { await model.observe() }
            while model.highlight == nil { await Task.yield() }
            #expect(model.copyText == expected)
            task.cancel()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func imageURLResolves() async throws {
        let session = try await Self.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        _ = try session.environment.fileStore.createDocumentFolder(documentId: Self.documentId)
        let created = try await session.environment.highlightService.createImage(NewImageHighlight(
            documentId: Self.documentId,
            pageIndex: 0,
            rect: CGRectCodable(x: 0, y: 0, width: 10, height: 10),
            positionKey: 0,
            color: .yellow,
            pngData: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ))
        let model = HighlightPopoverModel(highlightId: created.id, session: session)
        let task = Task { await model.observe() }
        while model.highlight == nil { await Task.yield() }

        let url = try #require(model.imageURL)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        task.cancel()
    }

    @Test(.timeLimit(.minutes(1)))
    func noteAndTagsPersist() async throws {
        let session = try await Self.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let environment = session.environment
        let highlight = TestData.highlight(documentId: Self.documentId)
        try await environment.highlightRepository.insert(highlight)
        let model = HighlightPopoverModel(highlightId: highlight.id, session: session)
        await model.noteModel.load()

        model.noteModel.text = "Why? #exam"
        await model.noteModel.flush()
        await model.tagModel.add(name: "ml")

        #expect(try await environment.highlightRepository.fetch(id: highlight.id)?.note == "Why? #exam")
        let names = try await environment.tagRepository.tags(forHighlight: highlight.id).map(\.name)
        #expect(Set(names) == ["exam", "ml"])
    }
}
