import Foundation
import GRDB
import Testing
@testable import StudyReader

@MainActor
@Suite("PendingWrites")
struct PendingWritesTests {
    private static let documentId = "40000000-0000-0000-0000-0000000000E1"
    private static let highlightId = "50000000-0000-0000-0000-0000000000E1"

    /// In-memory library with a ManualSleeper, so no debounce ever fires on its own.
    private static func makeEnvironment() throws -> AppEnvironment {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        return AppEnvironment(
            fileStore: base.fileStore,
            database: base.database,
            now: base.now,
            settingsStore: TestSettings.make(),
            sleeper: ManualSleeper()
        )
    }

    private static func cleanUp(_ environment: AppEnvironment) {
        TestFileStore.remove(environment.fileStore)
        TestSettings.remove(environment.settingsStore)
    }

    private static func seed(_ environment: AppEnvironment) async throws {
        try await environment.documentRepository.insert(TestData.document(id: documentId, title: "One"))
        try await environment.highlightRepository.insert(
            TestData.highlight(documentId: documentId, id: highlightId, positionKey: 10)
        )
    }

    private final class CountingWriter: PendingWriteFlushing {
        var flushes = 0
        func flushPendingWrites() async { flushes += 1 }
    }

    @Test(.timeLimit(.minutes(1)))
    func flushAllSavesNoteTypedWithinTheDebounce() async throws {
        let environment = try Self.makeEnvironment()
        defer { Self.cleanUp(environment) }
        try await Self.seed(environment)

        let document = NoteEditorModel(target: .document(Self.documentId), environment: environment)
        await document.load()
        let highlight = NoteEditorModel(target: .highlight(Self.highlightId), environment: environment)
        await highlight.load()
        document.text = "typed just before quit"
        highlight.text = "#exam why"

        await environment.pendingWrites.flushAll()

        #expect(try await environment.notesRepository.documentNote(documentId: Self.documentId)?.body == "typed just before quit")
        #expect(try await environment.highlightRepository.fetch(id: Self.highlightId)?.note == "#exam why")
        let tags = try await environment.tagRepository.tags(forHighlight: Self.highlightId)
        #expect(tags.map(\.name) == ["exam"])
    }

    @Test(.timeLimit(.minutes(1)))
    func flushAllSavesThePendingReadingPosition() async throws {
        let environment = try Self.makeEnvironment()
        defer { Self.cleanUp(environment) }
        try await Self.seed(environment)

        let model = ReaderModel(documentId: Self.documentId, session: AppSession(environment: environment))
        model.textPositionChanged(offset: 120, textLength: 1000)
        #expect(try await environment.documentRepository.fetch(id: Self.documentId)?.textPosition != 120)

        await environment.pendingWrites.flushAll()

        #expect(try await environment.documentRepository.fetch(id: Self.documentId)?.textPosition == 120)
    }

    @Test
    func registryIsWeak() async {
        let writes = PendingWrites()
        var first: CountingWriter? = CountingWriter()
        let second = CountingWriter()
        writes.register(first!)
        writes.register(second)
        #expect(writes.liveCount == 2)

        first = nil

        #expect(writes.liveCount == 1)
        await writes.flushAll()
        #expect(second.flushes == 1)
    }

    @Test
    func flushAllWithADeallocatedWriterCompletes() async {
        let writes = PendingWrites()
        var gone: CountingWriter? = CountingWriter()
        writes.register(gone!)
        gone = nil
        await writes.flushAll()
        #expect(writes.liveCount == 0)
    }

    @Test
    func registeringTwiceKeepsOneEntry() async {
        let writes = PendingWrites()
        let writer = CountingWriter()
        writes.register(writer)
        writes.register(writer)

        #expect(writes.liveCount == 1)
        await writes.flushAll()
        #expect(writer.flushes == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func flushStartedBeforeTheViewGoesAwayStillSaves() async throws {
        let environment = try Self.makeEnvironment()
        defer { Self.cleanUp(environment) }
        try await Self.seed(environment)

        var model: NoteEditorModel? = NoteEditorModel(target: .document(Self.documentId), environment: environment)
        await model?.load()
        model?.text = "kept after the view went away"
        let editor = try #require(model)
        let task = Task { await editor.flush() }
        model = nil
        await task.value

        #expect(try await environment.notesRepository.documentNote(documentId: Self.documentId)?.body == "kept after the view went away")
    }

    @Test(.timeLimit(.minutes(1)))
    func flushAfterTheTargetIsDeletedCreatesNothing() async throws {
        let environment = try Self.makeEnvironment()
        defer { Self.cleanUp(environment) }
        try await Self.seed(environment)

        let documentModel = NoteEditorModel(target: .document(Self.documentId), environment: environment)
        await documentModel.load()
        documentModel.text = "#ghost text"
        _ = try await environment.documentRepository.delete(id: Self.documentId, fileStore: environment.fileStore)

        await environment.pendingWrites.flushAll()

        #expect(try await environment.notesRepository.documentNote(documentId: Self.documentId) == nil)
        #expect(try await environment.tagRepository.fetchAll().contains { $0.name == "ghost" } == false)
        #expect(documentModel.lastError != nil)

        // A highlight target on a second document.
        let otherDocument = "40000000-0000-0000-0000-0000000000E2"
        let otherHighlight = "50000000-0000-0000-0000-0000000000E2"
        try await environment.documentRepository.insert(TestData.document(id: otherDocument, title: "Two"))
        try await environment.highlightRepository.insert(
            TestData.highlight(documentId: otherDocument, id: otherHighlight, positionKey: 5)
        )
        let highlightModel = NoteEditorModel(target: .highlight(otherHighlight), environment: environment)
        await highlightModel.load()
        highlightModel.text = "#ghost text"
        _ = try await environment.highlightRepository.delete(id: otherHighlight, fileStore: environment.fileStore)

        await environment.pendingWrites.flushAll()

        #expect(try await environment.highlightRepository.fetch(id: otherHighlight) == nil)
        #expect(try await environment.tagRepository.fetchAll().contains { $0.name == "ghost" } == false)
        #expect(highlightModel.lastError != nil)
        try await environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
