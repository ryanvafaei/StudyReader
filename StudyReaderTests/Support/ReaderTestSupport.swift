import Foundation
@testable import StudyReader

/// Shared setup for reader model tests: an in-memory library with an injected sleeper and a test settings store.
@MainActor
enum ReaderTestSupport {
    static func makeSession(sleeper: any Sleeper = ImmediateSleeper()) throws -> AppSession {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let environment = AppEnvironment(
            fileStore: base.fileStore,
            database: base.database,
            now: base.now,
            settingsStore: TestSettings.make(),
            sleeper: sleeper
        )
        return AppSession(environment: environment)
    }

    static func cleanUp(_ session: AppSession) {
        TestFileStore.remove(session.environment.fileStore)
        TestSettings.remove(session.environment.settingsStore)
    }

    /// Inserts a PDF document row. With `withFile`, also writes a real PDF to its original-file path.
    static func insertDocument(_ session: AppSession, id: String, withFile: Bool) async throws {
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: id))
        guard withFile else { return }
        _ = try environment.fileStore.createDocumentFolder(documentId: id)
        let url = try environment.fileStore.originalFileURL(documentId: id, fileType: .pdf)
        try PDFFixtureBuilder.plainMultiPage(pageCount: 10).write(to: url)
    }

    static func row(_ session: AppSession, id: String) async -> LibraryDocument? {
        try? await session.environment.documentRepository.fetch(id: id)
    }

    static func highlightCount(_ session: AppSession, documentId: String) async -> Int {
        (try? await session.environment.highlightRepository.fetchForDocument(documentId))?.count ?? 0
    }

    static func selection(
        documentId: String,
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

    /// Polls `condition` every 10 ms until it holds or `timeout` passes. Returns the last result.
    static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}
