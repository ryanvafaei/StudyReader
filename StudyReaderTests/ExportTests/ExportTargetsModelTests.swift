import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ExportTargetsModel")
struct ExportTargetsModelTests {
    @Test(.timeLimit(.minutes(1)))
    func folderLinkParsing() throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let model = ExportTargetsModel(session: session)

        model.folderLink = "https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp?usp=sharing"
        model.saveFolder()
        #expect(model.folderError == nil)
        #expect(session.settings.googleExportFolderId == "1AbCdEfGhIjKlMnOp")

        model.folderLink = "not a folder link!"
        model.saveFolder()
        #expect(model.folderError != nil)
        #expect(session.settings.googleExportFolderId == "1AbCdEfGhIjKlMnOp")

        model.folderLink = "  "
        model.saveFolder()
        #expect(model.folderError == nil)
        #expect(session.settings.googleExportFolderId == nil)
    }

    @Test
    func statusTexts() {
        func text(_ status: ExportStatus, error: String? = nil, exportedAt: Date? = nil) -> String {
            var target = TestData.exportTarget()
            target.lastStatus = status.rawValue
            target.lastError = error
            target.lastExportedAt = exportedAt
            return ExportTargetsModel.statusText(target)
        }
        #expect(text(.never) == "Never exported")
        #expect(text(.queued) == "Waiting for network")
        #expect(text(.docMissing) == "Doc missing")
        #expect(text(.signInRequired) == "Sign-in required")
        #expect(text(.failed, error: "boom").contains("boom"))
        #expect(text(.ok, exportedAt: TestData.referenceDate).hasPrefix("Exported"))
    }

    @Test(.timeLimit(.minutes(1)))
    func exportNowIgnoresASecondCallForTheSameTarget() async throws {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let gated = GatedHTTPClient([])
        let environment = AppEnvironment(
            fileStore: base.fileStore,
            database: base.database,
            now: base.now,
            settingsStore: TestSettings.make(),
            httpClient: gated,
            googleAuth: StubGoogleAuth()
        )
        let session = AppSession(environment: environment)
        defer { ReaderTestSupport.cleanUp(session) }
        let target = TestData.exportTarget()
        try await environment.exportRepository.insertTarget(target)

        let model = ExportTargetsModel(session: session)
        let first = Task { await model.exportNow(target.id) }
        var polls = 0
        while await gated.requestCount < 1, polls < 400 {
            polls += 1
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.exportingIds == [target.id])

        // A second call for the same target returns at once and sends nothing.
        await model.exportNow(target.id)
        #expect(await gated.requestCount == 1)
        #expect(model.exportingIds == [target.id])

        await gated.open()
        await first.value
        #expect(model.exportingIds.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportNowDoesNotBlockADifferentTarget() async throws {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let gated = GatedHTTPClient([])
        let environment = AppEnvironment(
            fileStore: base.fileStore,
            database: base.database,
            now: base.now,
            settingsStore: TestSettings.make(),
            httpClient: gated,
            googleAuth: StubGoogleAuth()
        )
        let session = AppSession(environment: environment)
        defer { ReaderTestSupport.cleanUp(session) }
        let target = TestData.exportTarget()
        let other = TestData.exportTarget()
        try await environment.exportRepository.insertTarget(target)
        try await environment.exportRepository.insertTarget(other)

        let model = ExportTargetsModel(session: session)
        let first = Task { await model.exportNow(target.id) }
        var polls = 0
        while await gated.requestCount < 1, polls < 400 {
            polls += 1
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.exportingIds == [target.id])

        // A different target is not blocked: its request reaches the client while the first is still held.
        let second = Task { await model.exportNow(other.id) }
        polls = 0
        while await gated.requestCount < 2, polls < 400 {
            polls += 1
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(await gated.requestCount == 2)
        #expect(model.exportingIds == [target.id, other.id])

        await gated.open()
        await first.value
        await second.value
        #expect(model.exportingIds.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func removeKeepsDoc() async throws {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let http = StubHTTPClient([])
        let environment = AppEnvironment(
            fileStore: base.fileStore,
            database: base.database,
            now: base.now,
            settingsStore: TestSettings.make(),
            httpClient: http,
            googleAuth: StubGoogleAuth()
        )
        let session = AppSession(environment: environment)
        defer { ReaderTestSupport.cleanUp(session) }
        var target = TestData.exportTarget()
        target.googleFileId = "FILE1"
        try await environment.exportRepository.insertTarget(target)

        let model = ExportTargetsModel(session: session)
        await model.remove(target.id)
        #expect(try await environment.exportRepository.fetchTargets().isEmpty)
        #expect(await http.requests.isEmpty)
        #expect(ExportTargetsModel.docURL(fileId: "FILE1").absoluteString == "https://docs.google.com/document/d/FILE1/edit")
    }
}
