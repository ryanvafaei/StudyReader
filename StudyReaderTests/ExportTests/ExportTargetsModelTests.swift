import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ExportTargetsModel")
struct ExportTargetsModelTests {
    @Test(.timeLimit(.minutes(1)))
    func appFolderFollowsTheAccount() throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        session.environment.settingsStore.setGoogleAppFolderId("F1", forAccount: "a@example.com")
        let model = ExportTargetsModel(session: session)

        model.refreshAppFolder(account: "a@example.com")
        #expect(model.appFolderId == "F1")
        model.refreshAppFolder(account: "b@example.com")
        #expect(model.appFolderId == nil)
        model.refreshAppFolder(account: "a@example.com")
        model.refreshAppFolder(account: nil)
        #expect(model.appFolderId == nil)
        #expect(ExportTargetsModel.folderURL(folderId: "F1").absoluteString == "https://drive.google.com/drive/folders/F1")
    }

    @Test(.timeLimit(.minutes(1)))
    func legacyFolderNoticeShowsOnce() throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let store = session.environment.settingsStore
        store.legacyGoogleExportFolderId = "PASTED123"

        let model = ExportTargetsModel(session: session)
        #expect(!model.showsLegacyFolderNotice)
        model.consumeLegacyFolderNotice()
        #expect(model.showsLegacyFolderNotice)
        #expect(store.defaults.object(forKey: "settings.googleExportFolderId") == nil)

        let again = ExportTargetsModel(session: session)
        again.consumeLegacyFolderNotice()
        #expect(!again.showsLegacyFolderNotice)

        store.legacyGoogleExportFolderId = "   "
        let blank = ExportTargetsModel(session: session)
        blank.consumeLegacyFolderNotice()
        #expect(!blank.showsLegacyFolderNotice)
        #expect(store.legacyGoogleExportFolderId == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportNowRefreshesTheAppFolder() async throws {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let about = StubHTTPClient.Reply.response(
            status: 200,
            body: #"{"importFormats":{"text/markdown":["application/vnd.google-apps.document"]}}"#
        )
        let http = StubHTTPClient([
            about,
            .response(status: 200, body: #"{"files":[]}"#),
            .response(status: 200, body: #"{"id":"APPFOLDER"}"#),
            .response(status: 200, body: #"{"id":"FILE1"}"#),
        ])
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
        let target = TestData.exportTarget()
        try await environment.exportRepository.insertTarget(target)

        let model = ExportTargetsModel(session: session)
        model.refreshAppFolder(account: "student@example.com")
        #expect(model.appFolderId == nil)
        await model.exportNow(target.id)
        #expect(model.appFolderId == "APPFOLDER")
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
