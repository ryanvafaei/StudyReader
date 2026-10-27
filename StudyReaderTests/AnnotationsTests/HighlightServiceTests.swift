import Foundation
import Testing
@testable import StudyReader

@Suite("HighlightService")
struct HighlightServiceTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000A1"

    private static func textSelection(
        text: String = "Selected text",
        color: HighlightColor = .yellow
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
            color: color
        )
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test(.timeLimit(.minutes(1)))
    func autoHighlightUndo() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let service = env.highlightService

        let created = try await service.createText(Self.textSelection(color: .pink), isAuto: true)
        let stored = try await env.highlightRepository.fetch(id: created.id)
        #expect(stored != nil)
        #expect(stored?.color == .pink)
        #expect(stored?.createdAt == TestData.referenceDate)

        let undone = try await service.undoAutoHighlight(id: created.id)
        #expect(undone == created.id)
        let afterUndo = try await env.highlightRepository.fetch(id: created.id)
        #expect(afterUndo == nil)

        let second = try await service.undoAutoHighlight(id: created.id)
        #expect(second == nil)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func undoOnlyRightAfter() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let service = env.highlightService

        // A color change after the auto-highlight cancels the undo.
        let h1 = try await service.createText(Self.textSelection(text: "First"), isAuto: true)
        try await service.setColor(id: h1.id, color: .blue)
        let undoAfterColor = try await service.undoAutoHighlight(id: h1.id)
        #expect(undoAfterColor == nil)
        let storedH1 = try await env.highlightRepository.fetch(id: h1.id)
        #expect(storedH1 != nil)
        #expect(storedH1?.color == .blue)

        // A non-auto highlight created after the auto-highlight cancels the undo.
        let h2 = try await service.createText(Self.textSelection(text: "Second"), isAuto: true)
        _ = try await service.createText(Self.textSelection(text: "Third"), isAuto: false)
        let undoAfterPlain = try await service.undoAutoHighlight(id: h2.id)
        #expect(undoAfterPlain == nil)
        let storedH2 = try await env.highlightRepository.fetch(id: h2.id)
        #expect(storedH2 != nil)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func undoOnlyDeletesTheCallersOwnAutoHighlight() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let service = env.highlightService

        let first = try await service.createText(Self.textSelection(text: "First"), isAuto: true)
        let second = try await service.createText(Self.textSelection(text: "Second"), isAuto: true)

        let undoFirst = try await service.undoAutoHighlight(id: first.id)
        #expect(undoFirst == nil)
        let storedFirst = try await env.highlightRepository.fetch(id: first.id)
        let storedSecond = try await env.highlightRepository.fetch(id: second.id)
        #expect(storedFirst != nil)
        #expect(storedSecond != nil)

        let undoSecond = try await service.undoAutoHighlight(id: second.id)
        #expect(undoSecond == second.id)
        let afterUndo = try await env.highlightRepository.fetch(id: second.id)
        #expect(afterUndo == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsEmptySelection() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let service = env.highlightService

        await #expect(throws: HighlightServiceError.emptySelection) {
            _ = try await service.createText(Self.textSelection(text: "  \n"), isAuto: false)
        }
        let rows = try await env.highlightRepository.fetchForDocument(Self.documentId)
        #expect(rows.isEmpty)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func createImageWritesPNG() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let rect = CGRectCodable(x: 10, y: 20, width: 100, height: 50)

        let created = try await env.highlightService.createImage(NewImageHighlight(
            documentId: Self.documentId,
            pageIndex: 2,
            rect: rect,
            positionKey: 2,
            color: .green,
            pngData: Self.pngSignature
        ))

        let url = try env.fileStore.snapshotURL(documentId: Self.documentId, highlightId: created.id)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let written = try Data(contentsOf: url)
        #expect(written == Self.pngSignature)
        #expect(created.imagePath == "\(Self.documentId)/snapshots/\(created.id).png")
        #expect(created.kind == .image)
        #expect(created.view == .pdf)
        #expect(created.anchor == .image(ImageAnchor(pageIndex: 2, rect: rect)))

        let stored = try await env.highlightRepository.fetch(id: created.id)
        #expect(stored == created)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteAndColorBulk() async throws {
        let clock = FixedNow(TestData.referenceDate)
        let env = try AppEnvironment.inMemory(now: clock)
        defer { TestFileStore.remove(env.fileStore) }
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))
        let service = env.highlightService
        let first = try await service.createText(Self.textSelection(text: "One"), isAuto: false)
        let second = try await service.createText(Self.textSelection(text: "Two"), isAuto: false)

        clock.advance(by: 60)
        let later = clock()
        try await service.setColor(ids: [first.id, second.id], color: .purple)
        let storedFirst = try await env.highlightRepository.fetch(id: first.id)
        let storedSecond = try await env.highlightRepository.fetch(id: second.id)
        #expect(storedFirst?.color == .purple)
        #expect(storedSecond?.color == .purple)
        #expect(storedFirst?.updatedAt == later)
        #expect(storedSecond?.updatedAt == later)

        try await service.delete(ids: [first.id, second.id])
        let afterFirst = try await env.highlightRepository.fetch(id: first.id)
        let afterSecond = try await env.highlightRepository.fetch(id: second.id)
        #expect(afterFirst == nil)
        #expect(afterSecond == nil)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
