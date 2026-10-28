import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ExportSheetModel")
struct ExportSheetModelTests {
    private static let docId = "10000000-0000-0000-0000-0000000000B1"
    private static let about = StubHTTPClient.Reply.response(
        status: 200,
        body: #"{"importFormats":{"text/markdown":["application/vnd.google-apps.document"]}}"#
    )

    @MainActor
    private struct Harness {
        let session: AppSession
        let http: StubHTTPClient

        init(replies: [StubHTTPClient.Reply], auth: any GoogleAuthProviding = StubGoogleAuth()) async throws {
            let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
            let http = StubHTTPClient(replies)
            let environment = AppEnvironment(
                fileStore: base.fileStore,
                database: base.database,
                now: base.now,
                settingsStore: TestSettings.make(),
                httpClient: http,
                googleAuth: auth
            )
            self.http = http
            self.session = AppSession(environment: environment)
            try await environment.documentRepository.insert(TestData.document(id: ExportSheetModelTests.docId, title: "Alpha"))
            try await environment.highlightRepository.insert(
                TestData.highlight(documentId: ExportSheetModelTests.docId, text: "Mitochondria")
            )
        }

        func cleanUp() { ReaderTestSupport.cleanUp(session) }
    }

    @Test(.timeLimit(.minutes(1)))
    func scopeRequiresId() async throws {
        let h = try await Harness(replies: [])
        defer { h.cleanUp() }
        let model = ExportSheetModel(session: h.session, initialScope: nil)
        #expect(model.scope == .all)

        model.scopeKind = .document
        #expect(model.scope == nil)
        #expect(model.canExport == false)

        model.selectedId = Self.docId
        #expect(model.scope == .document(Self.docId))
        await model.load()
        #expect(model.canExport)

        model.scopeKind = .tag
        #expect(model.selectedId == nil)
        #expect(model.scope == nil)
        model.selectedId = "tag-1"
        #expect(model.scope == .tag("tag-1"))

        model.scopeKind = .category
        #expect(model.selectedId == nil)
        #expect(model.scope == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func scopeWithoutTargetResetsOptions() async throws {
        let h = try await Harness(replies: [])
        defer { h.cleanUp() }
        var target = TestData.exportTarget(scope: .document(Self.docId))
        target.options = ExportOptions(includeNotes: false, includeDocumentNotes: false, includeImages: false, groupBy: .tag)
        try await h.session.environment.exportRepository.insertTarget(target)

        let model = ExportSheetModel(session: h.session, initialScope: .document(Self.docId))
        await model.load()
        #expect(model.options == target.options)

        model.scopeKind = .all
        await model.prefillOptions()
        #expect(model.options == ExportOptions())
    }

    @Test(.timeLimit(.minutes(1)))
    func optionsPrefillFromExistingTarget() async throws {
        let h = try await Harness(replies: [])
        defer { h.cleanUp() }
        var target = TestData.exportTarget(scope: .document(Self.docId))
        target.options = ExportOptions(includeNotes: false, includeDocumentNotes: false, includeImages: false, groupBy: .tag)
        try await h.session.environment.exportRepository.insertTarget(target)

        let model = ExportSheetModel(session: h.session, initialScope: .document(Self.docId))
        await model.load()
        #expect(model.options == target.options)

        let other = ExportSheetModel(session: h.session, initialScope: nil)
        await other.load()
        #expect(other.options == ExportOptions())
    }

    @Test(.timeLimit(.minutes(1)))
    func exportShowsOutcome() async throws {
        let h = try await Harness(replies: [Self.about, .response(status: 200, body: #"{"id": "FILE1"}"#)])
        defer { h.cleanUp() }
        let model = ExportSheetModel(session: h.session, initialScope: .document(Self.docId))
        await model.load()
        await model.export()
        #expect(model.outcome == .exported(fileId: "FILE1"))
        #expect(model.exportedFileId == "FILE1")
        #expect(model.isExporting == false)
        #expect(model.outcomeMessage == "Exported. The Google Doc is up to date.")
    }

    @Test(.timeLimit(.minutes(1)))
    func notConfiguredMakesNoRequest() async throws {
        let h = try await Harness(replies: [], auth: UnconfiguredGoogleAuth())
        defer { h.cleanUp() }
        let model = ExportSheetModel(session: h.session, initialScope: nil)
        await model.load()
        #expect(model.isConfigured == false)
        #expect(model.canExport == false)
        await model.export()
        #expect(model.outcome == .notConfigured)
        #expect(model.outcomeMessage == "Google export not configured.")
        #expect(await h.http.requests.count == 0)
    }
}
