import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("HighlightRepository")
struct HighlightRepositoryTests {
    private static let documentA = "10000000-0000-0000-0000-0000000000A1"
    private static let documentB = "10000000-0000-0000-0000-0000000000B2"

    /// Two documents so highlight rows have valid foreign keys.
    private static func seedDocuments(_ db: AppDatabase) async throws {
        let documents = DocumentRepository(database: db)
        try await documents.insert(TestData.document(id: documentA, title: "A"))
        try await documents.insert(TestData.document(id: documentB, title: "B"))
    }

    @Test(.timeLimit(.minutes(1)))
    func insertAndFetchForDocument() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let repo = HighlightRepository(database: db)
        let t0 = TestData.referenceDate
        // Expected order: positionKey, then createdAt, then id.
        let ten = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000C2", positionKey: 10)
        let twenty = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000C3", positionKey: 20)
        let thirty = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000C1", positionKey: 30)
        // Same positionKey 40, different createdAt: the earlier createdAt wins even though its id sorts later.
        let tiedEarlierCreated = TestData.highlight(
            documentId: Self.documentA,
            id: "20000000-0000-0000-0000-0000000000C9",
            positionKey: 40,
            createdAt: t0.addingTimeInterval(30)
        )
        let tiedLaterCreated = TestData.highlight(
            documentId: Self.documentA,
            id: "20000000-0000-0000-0000-0000000000C4",
            positionKey: 40,
            createdAt: t0.addingTimeInterval(60)
        )
        // Same positionKey and createdAt: id decides.
        let tiedHighId = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000C8", positionKey: 50)
        let tiedLowId = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000C7", positionKey: 50)
        let other = TestData.highlight(documentId: Self.documentB, id: "20000000-0000-0000-0000-0000000000D5", positionKey: 5)

        // Inserted out of order.
        let inserted = [tiedLaterCreated, tiedHighId, thirty, tiedLowId, twenty, other, tiedEarlierCreated, ten]
        for highlight in inserted {
            try await repo.insert(highlight)
        }

        let expectedOrder = [ten, twenty, thirty, tiedEarlierCreated, tiedLaterCreated, tiedLowId, tiedHighId]
            .map(\.id)
        let fetchedA = try await repo.fetchForDocument(Self.documentA)
        let fetchedOne = try await repo.fetch(id: ten.id)
        let unknown = try await repo.fetch(id: "20000000-0000-0000-0000-0000000000FF")

        #expect(fetchedA.map(\.id) == expectedOrder)
        #expect(fetchedOne == ten)
        #expect(unknown == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func insertWithTags() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let repo = HighlightRepository(database: db)
        let tagOne = TestData.tag(name: "Exam", id: "30000000-0000-0000-0000-0000000000D1")
        let tagTwo = TestData.tag(name: "Week 3", id: "30000000-0000-0000-0000-0000000000D2")
        try await db.writer.write { db in
            try tagOne.insert(db)
            try tagTwo.insert(db)
        }
        let highlight = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000E1")

        try await repo.insert(highlight, tagIds: [tagOne.id, tagTwo.id, tagOne.id])

        let links = try await db.writer.read { db in
            try HighlightTag
                .filter(Column("highlightId") == highlight.id)
                .order(Column("tagId"))
                .fetchAll(db)
        }
        #expect(links.map(\.tagId) == [tagOne.id, tagTwo.id].sorted())
        #expect(links.count == 2)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func updates() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let repo = HighlightRepository(database: db)
        let highlight = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000F1")
        try await repo.insert(highlight)
        let colorDate = TestData.referenceDate.addingTimeInterval(60)
        let noteDate = TestData.referenceDate.addingTimeInterval(120)
        let anchorDate = TestData.referenceDate.addingTimeInterval(180)
        let newAnchor = HighlightAnchor.text(TextAnchor(
            start: 5,
            length: 5,
            text: "moved",
            prefix: "a ",
            suffix: " b",
            sourceVersion: 2
        ))

        try await repo.updateColor(id: highlight.id, color: .green, at: colorDate)
        let afterColor = try #require(try await repo.fetch(id: highlight.id))
        #expect(afterColor.color == .green)
        #expect(afterColor.updatedAt == colorDate)

        try await repo.updateNote(id: highlight.id, note: "Remember this", at: noteDate)
        let afterNote = try #require(try await repo.fetch(id: highlight.id))
        #expect(afterNote.note == "Remember this")
        #expect(afterNote.color == .green)
        #expect(afterNote.updatedAt == noteDate)

        let noteHits = try await db.writer.read { db in
            try Int.fetchAll(db, sql: "SELECT rowid FROM highlight_fts WHERE highlight_fts MATCH ?", arguments: ["remember"])
        }
        let highlightRowid = try #require(try await db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT rowid FROM highlight WHERE id = ?", arguments: [highlight.id])
        })
        #expect(noteHits == [highlightRowid])

        try await repo.updateAnchor(
            id: highlight.id,
            anchor: newAnchor,
            positionKey: 5,
            status: .orphaned,
            at: anchorDate
        )

        let fetched = try #require(try await repo.fetch(id: highlight.id))
        #expect(fetched.color == .green)
        #expect(fetched.note == "Remember this")
        #expect(fetched.anchor == newAnchor)
        #expect(fetched.positionKey == 5)
        #expect(fetched.anchorStatus == .orphaned)
        #expect(fetched.updatedAt == anchorDate)
        #expect(fetched.text == highlight.text)
        #expect(fetched.createdAt == highlight.createdAt)

        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateColor(id: "20000000-0000-0000-0000-0000000000FE", color: .blue, at: colorDate)
        }
        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateNote(id: "20000000-0000-0000-0000-0000000000FE", note: "x", at: noteDate)
        }
        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateAnchor(
                id: "20000000-0000-0000-0000-0000000000FE",
                anchor: newAnchor,
                positionKey: 5,
                status: .ok,
                at: anchorDate
            )
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteRemovesSnapshotFile() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        try fileStore.createRootDirectories()
        let repo = HighlightRepository(database: db)
        let imageId = "20000000-0000-0000-0000-0000000000A9"
        var image = TestData.highlight(documentId: Self.documentA, id: imageId)
        image.kind = .image
        image.view = .pdf
        image.anchor = .image(ImageAnchor(pageIndex: 0, rect: CGRectCodable(x: 0, y: 0, width: 20, height: 20)))
        image.imagePath = "\(Self.documentA)/snapshots/\(imageId).png"
        let snapshot = try fileStore.snapshotURL(documentId: Self.documentA, highlightId: imageId)
        try FileManager.default.createDirectory(
            at: snapshot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: snapshot)
        try await repo.insert(image)
        let existedBefore = FileManager.default.fileExists(atPath: snapshot.path(percentEncoded: false))

        let removed = try await repo.delete(id: imageId, fileStore: fileStore)
        let removedAgain = try await repo.delete(id: imageId, fileStore: fileStore)

        #expect(existedBefore)
        #expect(removed)
        #expect(removedAgain == false)
        #expect(FileManager.default.fileExists(atPath: snapshot.path(percentEncoded: false)) == false)
        #expect(try await repo.fetch(id: imageId) == nil)

        let textId = "20000000-0000-0000-0000-0000000000A8"
        let text = TestData.highlight(documentId: Self.documentA, id: textId)
        #expect(text.imagePath == nil)
        try await repo.insert(text)
        let removedText = try await repo.delete(id: textId, fileStore: fileStore)

        #expect(removedText)
        #expect(try await repo.fetch(id: textId) == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteIfUnannotatedKeepsAnnotatedRows() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let repo = HighlightRepository(database: db)
        var noted = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000021")
        noted.note = "x"
        var edited = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000022")
        edited.editedText = "e"
        let tagged = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000023")
        var blankNote = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000024")
        blankNote.note = " \n\t"
        let bare = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000025")
        let tag = TestData.tag(name: "Exam", id: "30000000-0000-0000-0000-0000000000D9")
        try await db.writer.write { db in try tag.insert(db) }
        for highlight in [noted, edited, blankNote, bare] {
            try await repo.insert(highlight)
        }
        try await repo.insert(tagged, tagIds: [tag.id])

        let keptNote = try await repo.deleteIfUnannotated(id: noted.id, fileStore: fileStore)
        let keptEdited = try await repo.deleteIfUnannotated(id: edited.id, fileStore: fileStore)
        let keptTagged = try await repo.deleteIfUnannotated(id: tagged.id, fileStore: fileStore)
        let removedBlank = try await repo.deleteIfUnannotated(id: blankNote.id, fileStore: fileStore)
        let removedBare = try await repo.deleteIfUnannotated(id: bare.id, fileStore: fileStore)
        let unknown = try await repo.deleteIfUnannotated(
            id: "20000000-0000-0000-0000-0000000000FC",
            fileStore: fileStore
        )

        #expect(keptNote == false)
        #expect(keptEdited == false)
        #expect(keptTagged == false)
        #expect(removedBlank)
        #expect(removedBare)
        #expect(unknown == false)
        let remaining = try await repo.fetchForDocument(Self.documentA)
        #expect(Set(remaining.map(\.id)) == [noted.id, edited.id, tagged.id])
        let links = try await db.writer.read { db in
            try HighlightTag.filter(Column("highlightId") == tagged.id).fetchAll(db)
        }
        #expect(links.map(\.tagId) == [tag.id])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func bulkColorAndDelete() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let repo = HighlightRepository(database: db)
        let first = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000011")
        let second = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000012")
        let third = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-000000000013")
        for highlight in [first, second, third] {
            try await repo.insert(highlight)
        }
        let edited = TestData.referenceDate.addingTimeInterval(900)

        let recolored = try await repo.updateColor(
            ids: [first.id, second.id, "20000000-0000-0000-0000-0000000000FD"],
            color: .purple,
            at: edited
        )
        let deleted = try await repo.delete(ids: [second.id, third.id], fileStore: fileStore)

        #expect(recolored == 2)
        #expect(deleted == 2)
        let remaining = try await repo.fetchForDocument(Self.documentA)
        #expect(remaining.map(\.id) == [first.id])
        #expect(remaining.first?.color == .purple)
        #expect(remaining.first?.updatedAt == edited)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeForDocumentEmits() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seedDocuments(db)
        let repo = HighlightRepository(database: db)
        let observation = repo.observeForDocument(Self.documentA)

        let added = TestData.highlight(documentId: Self.documentA, id: "20000000-0000-0000-0000-0000000000B1")
        var iterator = observation.makeAsyncIterator()
        let initial = try await iterator.next()
        try await repo.insert(added)
        let afterInsert = try await iterator.next()
        try await repo.updateColor(id: added.id, color: .pink, at: TestData.referenceDate.addingTimeInterval(60))
        let afterColor = try await iterator.next()

        #expect(initial == [])
        #expect(afterInsert?.map(\.id) == [added.id])
        #expect(afterColor?.map(\.id) == [added.id])
        #expect(afterColor?.first?.color == .pink)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
