import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("NotesRepository")
struct NotesRepositoryTests {
    private static let documentOne = "10000000-0000-0000-0000-0000000000E1"
    private static let highlightOne = "20000000-0000-0000-0000-0000000000E1"

    /// Polls `condition` every 5 ms for up to about 10 s. Used for effects that run on other tasks after `resumeAll()`.
    @MainActor
    private static func waitUntil(_ condition: @MainActor () async throws -> Bool) async throws {
        for _ in 0..<2_000 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private static func storedDocumentBody(_ db: AppDatabase) async throws -> String? {
        try await NotesRepository(database: db).documentNote(documentId: documentOne)?.body
    }

    private static func storedHighlightNote(_ db: AppDatabase) async throws -> String? {
        try await HighlightRepository(database: db).fetch(id: highlightOne)?.note
    }

    /// Opens one editing session on disk, types into both notes, then returns. The environment is released on return,
    /// so the caller can reopen the same store.
    @MainActor
    private static func editNotesOnDisk(fileStore: FileStore) async throws {
        let sleeper = ManualSleeper()
        let database = try AppDatabase.makeShared(fileStore: fileStore)
        let env = AppEnvironment(
            fileStore: fileStore,
            database: database,
            now: FixedNow(TestData.referenceDate),
            sleeper: sleeper
        )
        try await env.documentRepository.insert(TestData.document(id: documentOne, title: "One"))
        try await env.highlightRepository.insert(
            TestData.highlight(documentId: documentOne, id: highlightOne, positionKey: 10)
        )

        let document = NoteEditorModel(target: .document(documentOne), environment: env)
        await document.load()
        document.text = "a"
        document.text = "ab"
        document.text = "abc"
        await sleeper.waitForSleepers(3)
        await sleeper.resumeAll()
        try await waitUntil { try await storedDocumentBody(database) == "abc" }

        let highlight = NoteEditorModel(target: .highlight(highlightOne), environment: env)
        await highlight.load()
        highlight.text = "Check #review"
        await highlight.flush()
        await sleeper.resumeAll()
        #expect(try await storedHighlightNote(database) == "Check #review")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func autosaveAndRestore() async throws {
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }

        try await Self.editNotesOnDisk(fileStore: fileStore)

        let reopened = try AppDatabase.makeShared(fileStore: fileStore)
        let env = AppEnvironment(
            fileStore: fileStore,
            database: reopened,
            now: FixedNow(TestData.referenceDate),
            sleeper: ImmediateSleeper()
        )
        #expect(try await Self.storedDocumentBody(reopened) == "abc")
        #expect(try await Self.storedHighlightNote(reopened) == "Check #review")

        let document = NoteEditorModel(target: .document(Self.documentOne), environment: env)
        await document.load()
        #expect(document.text == "abc")
        let highlight = NoteEditorModel(target: .highlight(Self.highlightOne), environment: env)
        await highlight.load()
        #expect(highlight.text == "Check #review")
        try await reopened.writer.write { db in try FTSIntegrity.check(db) }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func onlyLastEditIsSaved() async throws {
        let sleeper = ManualSleeper()
        let database = try AppDatabase.makeInMemory()
        let env = AppEnvironment(
            fileStore: TestFileStore.make(),
            database: database,
            now: FixedNow(TestData.referenceDate),
            sleeper: sleeper
        )
        try await env.documentRepository.insert(TestData.document(id: Self.documentOne, title: "One"))

        let model = NoteEditorModel(target: .document(Self.documentOne), environment: env)
        await model.load()
        model.text = "x"
        model.text = "xy"
        model.text = "xyz"
        await sleeper.waitForSleepers(3)

        // Nothing is saved while the timers are pending.
        #expect(try await Self.storedDocumentBody(database) == nil)

        await sleeper.resumeAll()
        try await Self.waitUntil { try await Self.storedDocumentBody(database) == "xyz" }
        #expect(try await Self.storedDocumentBody(database) == "xyz")
        #expect(await sleeper.requested.allSatisfy { $0 == NoteEditorModel.autosaveDelay })
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func hashTagsAddTagsOnSave() async throws {
        let sleeper = ManualSleeper()
        let database = try AppDatabase.makeInMemory()
        let env = AppEnvironment(
            fileStore: TestFileStore.make(),
            database: database,
            now: FixedNow(TestData.referenceDate),
            sleeper: sleeper
        )
        try await env.documentRepository.insert(TestData.document(id: Self.documentOne, title: "One"))
        try await env.highlightRepository.insert(
            TestData.highlight(documentId: Self.documentOne, id: Self.highlightOne, positionKey: 10)
        )

        let model = NoteEditorModel(target: .highlight(Self.highlightOne), environment: env)
        await model.load()
        model.text = "Review #Exam and #ml-basics, see #exam"
        await model.flush()
        await sleeper.resumeAll()

        let tagNames = try await env.tagRepository.tags(forHighlight: Self.highlightOne).map(\.name)
        #expect(tagNames == ["Exam", "ml-basics"])
        let linkCount = try await database.writer.read { db in try HighlightTag.fetchCount(db) }
        #expect(linkCount == 2)

        // Removing a #tag from the note leaves the tag in place.
        model.text = "nothing"
        await model.flush()
        await sleeper.resumeAll()
        #expect(try await Self.storedHighlightNote(database) == "nothing")
        let afterRemoval = try await env.tagRepository.tags(forHighlight: Self.highlightOne).map(\.name)
        #expect(afterRemoval == ["Exam", "ml-basics"])
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentNoteUsesPrimaryKeyUpsert() async throws {
        let database = try AppDatabase.makeInMemory()
        try await DocumentRepository(database: database).insert(TestData.document(id: Self.documentOne, title: "One"))
        let notes = NotesRepository(database: database)
        let first = TestData.referenceDate
        let second = first.addingTimeInterval(60)

        try await notes.saveDocumentNote(documentId: Self.documentOne, body: "first", at: first)
        try await notes.saveDocumentNote(documentId: Self.documentOne, body: "second", at: second)

        let count = try await database.writer.read { db in try DocumentNote.fetchCount(db) }
        #expect(count == 1)
        let stored = try await notes.documentNote(documentId: Self.documentOne)
        #expect(stored?.body == "second")
        #expect(stored?.updatedAt == second)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
