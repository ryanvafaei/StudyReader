import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ExportRepository")
struct ExportRepositoryTests {
    private static let docA = "10000000-0000-0000-0000-0000000000A1"
    private static let docB = "10000000-0000-0000-0000-0000000000B2"
    private static let docC = "10000000-0000-0000-0000-0000000000C3"
    private static let docD = "10000000-0000-0000-0000-0000000000D4"
    private static let tagExam = "30000000-0000-0000-0000-0000000000E1"
    private static let tagML = "30000000-0000-0000-0000-0000000000E2"
    private static let hA1 = "20000000-0000-0000-0000-0000000000A1"
    private static let hA2 = "20000000-0000-0000-0000-0000000000A2"
    private static let hB1 = "20000000-0000-0000-0000-0000000000B1"
    private static let hB2 = "20000000-0000-0000-0000-0000000000B2"
    private static let review = "40000000-0000-0000-0000-0000000000F1"

    /// Documents: A "Alpha" (Lecture slides, note), B "beta" (Paper, author), C "Gamma" (Paper, note only),
    /// D "Delta" (Lecture slides, blank note). Highlights: A1 yellow exam+ml, A2 green ml, B1 blue exam, B2 image.
    private static func makeDatabase() async throws -> AppDatabase {
        let db = try AppDatabase.makeInMemory()
        let documents = DocumentRepository(database: db)
        try await documents.insert(TestData.document(id: docA, title: "Alpha", categoryId: BuiltinCategory.lectureSlides.id))
        var beta = TestData.document(id: docB, title: "beta", categoryId: BuiltinCategory.paper.id)
        beta.author = "Bea"
        try await documents.insert(beta)
        try await documents.insert(TestData.document(id: docC, title: "Gamma", categoryId: BuiltinCategory.paper.id))
        try await documents.insert(TestData.document(id: docD, title: "Delta", categoryId: BuiltinCategory.lectureSlides.id))

        let exam = TestData.tag(name: "exam", id: tagExam)
        let ml = TestData.tag(name: "ML", id: tagML)
        let themed = ThemedReview(
            id: review,
            name: "Exam week",
            filter: ThemedReviewFilter(tagIds: [tagExam, tagML], tagMode: .all, colors: [.yellow]),
            createdAt: TestData.referenceDate
        )
        try await db.writer.write { db in
            try exam.insert(db)
            try ml.insert(db)
            try themed.insert(db)
        }

        let highlights = HighlightRepository(database: db)
        try await highlights.insert(
            TestData.highlight(documentId: docA, id: hA1, text: "First", note: "  a note \n", color: .yellow, positionKey: 20),
            tagIds: [tagExam, tagML]
        )
        try await highlights.insert(
            TestData.highlight(documentId: docA, id: hA2, text: "Second", color: .green, positionKey: 10),
            tagIds: [tagML]
        )
        try await highlights.insert(
            TestData.highlight(documentId: docB, id: hB1, text: "Third", color: .blue, positionKey: 5),
            tagIds: [tagExam]
        )
        var image = TestData.highlight(documentId: docB, id: hB2, text: "", color: .pink, positionKey: 1)
        image.kind = .image
        image.pageIndex = 3
        image.richText = ""
        try await highlights.insert(image)

        let notes = NotesRepository(database: db)
        try await notes.saveDocumentNote(documentId: docA, body: "  A note \n", at: TestData.referenceDate)
        try await notes.saveDocumentNote(documentId: docC, body: "C note", at: TestData.referenceDate)
        try await notes.saveDocumentNote(documentId: docD, body: "  \n ", at: TestData.referenceDate)
        return db
    }

    private static func checkFTS(_ db: AppDatabase) async throws {
        try await db.writer.write { try FTSIntegrity.check($0) }
    }

    private func titles(_ content: ExportContent) -> [String] {
        content.documents.map(\.title)
    }

    private func highlightIds(_ content: ExportContent) -> [[String]] {
        content.documents.map { $0.highlights.map(\.id) }
    }

    @Test(.timeLimit(.minutes(1)))
    func scopeNames() async throws {
        let db = try await Self.makeDatabase()
        let repo = ExportRepository(database: db)
        #expect(try await repo.scopeName(for: .all) == "All highlights")
        #expect(try await repo.scopeName(for: .document(Self.docB)) == "beta")
        #expect(try await repo.scopeName(for: .tag(Self.tagML)) == "#ML")
        #expect(try await repo.scopeName(for: .category(BuiltinCategory.paper.id)) == "Paper")
        #expect(try await repo.scopeName(for: .themedReview(Self.review)) == "Exam week")
        await #expect(throws: RepositoryError.notFound) {
            _ = try await repo.scopeName(for: .document("missing"))
        }
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func documentScope() async throws {
        let db = try await Self.makeDatabase()
        let content = try await ExportRepository(database: db).content(for: .document(Self.docA))
        #expect(content.scopeName == "Alpha")
        #expect(titles(content) == ["Alpha"])
        #expect(highlightIds(content) == [[Self.hA2, Self.hA1]])
        let document = try #require(content.documents.first)
        #expect(document.documentNote == "A note")
        #expect(document.categoryName == "Lecture slides")
        let first = try #require(document.highlights.last)
        #expect(first.note == "a note")
        #expect(first.tagNames == ["exam", "ML"])
        #expect(first.body == "First")
        #expect(first.color == .yellow)
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func tagScope() async throws {
        let db = try await Self.makeDatabase()
        let content = try await ExportRepository(database: db).content(for: .tag(Self.tagExam))
        #expect(content.scopeName == "#exam")
        #expect(titles(content) == ["Alpha", "beta"])
        #expect(highlightIds(content) == [[Self.hA1], [Self.hB1]])
        #expect(content.documents[0].documentNote == "A note")
        #expect(content.documents[1].author == "Bea")
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func categoryScope() async throws {
        let db = try await Self.makeDatabase()
        let repo = ExportRepository(database: db)
        let paper = try await repo.content(for: .category(BuiltinCategory.paper.id))
        #expect(titles(paper) == ["beta", "Gamma"])
        #expect(highlightIds(paper) == [[Self.hB2, Self.hB1], []])
        #expect(paper.documents[1].documentNote == "C note")

        let lectures = try await repo.content(for: .category(BuiltinCategory.lectureSlides.id))
        #expect(titles(lectures) == ["Alpha"])
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func themedReviewScope() async throws {
        let db = try await Self.makeDatabase()
        let content = try await ExportRepository(database: db).content(for: .themedReview(Self.review))
        #expect(content.scopeName == "Exam week")
        #expect(titles(content) == ["Alpha"])
        #expect(highlightIds(content) == [[Self.hA1]])
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func allScope() async throws {
        let db = try await Self.makeDatabase()
        let content = try await ExportRepository(database: db).content(for: .all)
        #expect(content.scopeName == "All highlights")
        #expect(titles(content) == ["Alpha", "beta", "Gamma"])
        #expect(highlightIds(content) == [[Self.hA2, Self.hA1], [Self.hB2, Self.hB1], []])
        let image = try #require(content.documents[1].highlights.first)
        #expect(image.kind == .image)
        #expect(image.body == "")
        #expect(image.pageIndex == 3)
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionContent() async throws {
        let db = try await Self.makeDatabase()
        let content = try await ExportRepository(database: db)
            .content(forHighlightIds: [Self.hB1, Self.hA2], scopeName: "Selection")
        #expect(content.scopeName == "Selection")
        #expect(titles(content) == ["Alpha", "beta"])
        #expect(highlightIds(content) == [[Self.hA2], [Self.hB1]])
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func contentForHighlightIdsReadsOnlyThose() async throws {
        let db = try await Self.makeDatabase()
        let hC1 = "20000000-0000-0000-0000-0000000000C1"
        try await HighlightRepository(database: db).insert(
            TestData.highlight(documentId: Self.docC, id: hC1, text: "Fifth", positionKey: 1)
        )
        let content = try await ExportRepository(database: db)
            .content(forHighlightIds: [Self.hA1, hC1], scopeName: "x")
        #expect(content.scopeName == "x")
        #expect(titles(content) == ["Alpha", "Gamma"])
        #expect(highlightIds(content) == [[Self.hA1], [hC1]])
        #expect(content.documents[0].documentNote == "A note")
        #expect(content.documents[1].documentNote == "C note")
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func fetchThemedReviewsOrdersByName() async throws {
        let db = try AppDatabase.makeInMemory()
        let t0 = TestData.referenceDate
        try await db.writer.write { db in
            try TestData.themedReview(name: "beta", id: "40000000-0000-0000-0000-0000000000B1", createdAt: t0).insert(db)
            try TestData.themedReview(name: "Alpha", id: "40000000-0000-0000-0000-0000000000A1", createdAt: t0).insert(db)
            try TestData.themedReview(name: "gamma", id: "40000000-0000-0000-0000-0000000000C1", createdAt: t0).insert(db)
        }
        let reviews = try await ExportRepository(database: db).fetchThemedReviews()
        #expect(reviews.map(\.name) == ["Alpha", "beta", "gamma"])
    }

    @Test(.timeLimit(.minutes(1)))
    func bodyFollowsEditedTextThenRichTextThenText() async throws {
        let db = try await Self.makeDatabase()
        let highlights = HighlightRepository(database: db)
        var rich = TestData.highlight(documentId: Self.docC, id: "20000000-0000-0000-0000-0000000000C1", text: "a*b", positionKey: 1)
        rich.richText = "a\\*b **bold**"
        var plain = TestData.highlight(documentId: Self.docC, id: "20000000-0000-0000-0000-0000000000C2", text: "a*b_c", positionKey: 2)
        plain.richText = ""
        try await highlights.insert(rich)
        try await highlights.insert(plain)
        let content = try await ExportRepository(database: db).content(for: .document(Self.docC))
        #expect(content.documents.first?.highlights.map(\.body) == ["a\\*b **bold**", "a\\*b\\_c"])
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func targetsCRUD() async throws {
        let db = try await Self.makeDatabase()
        let repo = ExportRepository(database: db)
        let t0 = TestData.referenceDate
        let first = TestData.exportTarget(scope: .document(Self.docA), id: "t1", createdAt: t0)
        let second = TestData.exportTarget(scope: .all, id: "t2", createdAt: t0.addingTimeInterval(10))
        try await repo.insertTarget(second)
        try await repo.insertTarget(first)

        #expect(try await repo.fetchTargets().map(\.id) == ["t1", "t2"])
        #expect(try await repo.fetchTarget(id: "t2") == second)
        #expect(try await repo.fetchTarget(id: "nope") == nil)
        #expect(try await repo.target(for: .all)?.id == "t2")
        #expect(try await repo.target(for: .document(Self.docA))?.id == "t1")
        #expect(try await repo.target(for: .tag(Self.tagML)) == nil)

        let options = ExportOptions(includeNotes: false, includeDocumentNotes: true, includeImages: false, groupBy: .tag)
        try await repo.updateOptions(id: "t1", options: options, title: "Renamed")
        try await repo.setKeepInSync(id: "t1", true)
        var stored = try #require(try await repo.fetchTarget(id: "t1"))
        #expect(stored.options == options)
        #expect(stored.title == "Renamed")
        #expect(stored.keepInSync)
        #expect(stored.lastStatus == "never")
        #expect(stored.scope == .document(Self.docA))

        let exportedAt = t0.addingTimeInterval(100)
        try await repo.recordResult(
            id: "t1", status: .ok, error: nil, fileId: "file-1", folderId: "folder-1", format: .html, exportedAt: exportedAt
        )
        stored = try #require(try await repo.fetchTarget(id: "t1"))
        #expect(stored.lastStatus == "ok")
        #expect(stored.googleFileId == "file-1")
        #expect(stored.googleFolderId == "folder-1")
        #expect(stored.format == .html)
        #expect(stored.lastExportedAt == exportedAt)
        let storedType = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(lastExportedAt) FROM exportTarget WHERE id = 't1'")
        }
        #expect(storedType == "real")

        try await repo.recordResult(
            id: "t1", status: .failed, error: "Offline", fileId: nil, folderId: nil, format: nil, exportedAt: nil
        )
        stored = try #require(try await repo.fetchTarget(id: "t1"))
        #expect(stored.lastStatus == "failed")
        #expect(stored.lastError == "Offline")
        #expect(stored.googleFileId == "file-1")
        #expect(stored.googleFolderId == "folder-1")
        #expect(stored.format == .html)
        #expect(stored.lastExportedAt == exportedAt)
        #expect(stored.title == "Renamed")
        #expect(stored.options == options)
        #expect(stored.keepInSync)

        try await repo.recordResult(
            id: "t1", status: .ok, error: nil, fileId: nil, folderId: nil, format: nil, exportedAt: nil
        )
        #expect(try await repo.fetchTarget(id: "t1")?.lastError == nil)

        try await repo.clearFileId(id: "t1")
        stored = try #require(try await repo.fetchTarget(id: "t1"))
        #expect(stored.googleFileId == nil)
        #expect(stored.googleFolderId == "folder-1")

        try await repo.removeTarget(id: "t1")
        #expect(try await repo.fetchTargets().map(\.id) == ["t2"])
        try await repo.removeTarget(id: "t1")

        await #expect(throws: RepositoryError.notFound) {
            try await repo.setKeepInSync(id: "t1", true)
        }
        try await Self.checkFTS(db)
    }

    @Test(.timeLimit(.minutes(1)))
    func recordResultKeepsFolderWhenNil() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ExportRepository(database: db)
        var target = TestData.exportTarget(id: "t1")
        target.googleFolderId = "F"
        try await repo.insertTarget(target)

        try await repo.recordResult(
            id: "t1", status: .ok, error: nil, fileId: "file-1", folderId: nil, format: .markdown,
            exportedAt: TestData.referenceDate
        )
        let stored = try #require(try await repo.fetchTarget(id: "t1"))
        #expect(stored.googleFolderId == "F")
        #expect(stored.googleFileId == "file-1")
    }

    @Test(.timeLimit(.minutes(1)))
    func changeTokenFollowsSameLengthNoteEdit() async throws {
        let db = try await Self.makeDatabase()
        let repo = ExportRepository(database: db)
        let highlights = HighlightRepository(database: db)
        try await highlights.updateNote(id: Self.hA2, note: "ab", at: TestData.referenceDate.addingTimeInterval(60))

        var iterator = repo.observeChangeToken().makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first != nil)

        try await highlights.updateNote(id: Self.hA2, note: "ac", at: TestData.referenceDate.addingTimeInterval(120))
        let second = try await iterator.next()
        #expect(second != nil)
        #expect(second != first)
    }

    @Test(.timeLimit(.minutes(1)))
    func observeTargetsEmitsCurrentValue() async throws {
        let db = try await Self.makeDatabase()
        let repo = ExportRepository(database: db)
        try await repo.insertTarget(TestData.exportTarget(id: "t1"))
        var iterator = repo.observeTargets().makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id) == ["t1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func changeTokenEmits() async throws {
        let db = try await Self.makeDatabase()
        let repo = ExportRepository(database: db)
        var iterator = repo.observeChangeToken().makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first != nil)

        try await HighlightRepository(database: db).updateNote(
            id: Self.hA2, note: "A new note", at: TestData.referenceDate.addingTimeInterval(60)
        )
        let second = try await iterator.next()
        #expect(second != nil)
        #expect(second != first)
        try await Self.checkFTS(db)
    }
}
