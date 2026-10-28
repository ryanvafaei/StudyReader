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
