import Foundation
import Testing
@testable import StudyReader

/// Returns at once and records the requested durations.
private actor RecordingSleeper: Sleeper {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }
}

@Suite("GoogleExportService")
struct GoogleExportServiceTests {
    private static let aboutMarkdown = #"{"importFormats":{"text/markdown":["application/vnd.google-apps.document"]}}"#
    private static let aboutNoMarkdown = #"{"importFormats":{"text/html":["application/vnd.google-apps.document"]}}"#
    private static let docId = "10000000-0000-0000-0000-0000000000A1"
    private static let highlightId = "20000000-0000-0000-0000-0000000000A1"

    private struct Harness {
        let repository: ExportRepository
        let http: StubHTTPClient
        let auth: StubGoogleAuth
        let sleeper = RecordingSleeper()
        let settings: SettingsStore
        let now = FixedNow(TestData.referenceDate)
        let service: GoogleExportService

        init(replies: [StubHTTPClient.Reply], auth: StubGoogleAuth = StubGoogleAuth()) async throws {
            let database = try AppDatabase.makeInMemory()
            let documents = DocumentRepository(database: database)
            try await documents.insert(TestData.document(id: GoogleExportServiceTests.docId, title: "Alpha"))
            try await HighlightRepository(database: database).insert(
                TestData.highlight(
                    documentId: GoogleExportServiceTests.docId,
                    id: GoogleExportServiceTests.highlightId,
                    text: "Mitochondria are the powerhouse"
                )
            )
            let repository = ExportRepository(database: database)
            let http = StubHTTPClient(replies)
            let settings = TestSettings.make()
            self.repository = repository
            self.http = http
            self.auth = auth
            self.settings = settings
            self.service = GoogleExportService(
                auth: auth,
                http: http,
                repository: repository,
                settings: settings,
                now: now,
                sleeper: sleeper,
                timeZone: TimeZone(identifier: "UTC") ?? .gmt,
                colorLabels: { ["Yellow", "Green", "Blue", "Pink", "Purple"] }
            )
        }

        func target(_ id: String?) async throws -> ExportTarget {
            let id = try #require(id)
            return try #require(try await repository.fetchTarget(id: id))
        }

        func body(_ index: Int) async throws -> String {
            let requests = await http.requests
            let request = try #require(requests.indices.contains(index) ? requests[index] : nil)
            return String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        }
    }

    private static func ok(_ id: String) -> StubHTTPClient.Reply {
        .response(status: 200, body: #"{"id": "\#(id)"}"#)
    }

    private static let about = StubHTTPClient.Reply.response(status: 200, body: aboutMarkdown)

    // MARK: Create and update

    @Test func createThenUpdate() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("FILE1"), Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }

        let first = await h.service.exportScope(.all, options: ExportOptions())
        #expect(first.outcome == .exported(fileId: "FILE1"))
        let target = try await h.target(first.targetId)
        #expect(target.googleFileId == "FILE1")
        #expect(target.lastStatus == "ok")
        #expect(target.lastExportedAt == TestData.referenceDate)
        #expect(target.lastError == nil)
        #expect(target.format == .markdown)
        #expect(target.title == "StudyReader – All highlights")

        var requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST"])
        #expect(requests[0].url?.path() == "/drive/v3/about")
        #expect(requests[1].url?.path() == "/upload/drive/v3/files")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let createBody = try await h.body(1)
        #expect(createBody.contains("# StudyReader – All highlights"))
        #expect(createBody.contains("Mitochondria are the powerhouse"))

        h.now.advance(by: 60)
        let second = await h.service.exportScope(.all, options: ExportOptions())
        #expect(second.targetId == first.targetId)
        #expect(second.outcome == .exported(fileId: "FILE1"))
        requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
        #expect(requests[2].url?.path() == "/upload/drive/v3/files/FILE1")
        let updated = try await h.target(first.targetId)
        #expect(updated.googleFileId == "FILE1")
        #expect(updated.lastExportedAt == TestData.referenceDate.addingTimeInterval(60))
        #expect(try await h.repository.fetchTargets().count == 1)
    }

    // MARK: Serialization and content hash (T74)

    @Test func concurrentExportsOfOneTargetRunOneAfterAnother() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("FILE1"), Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        let target = TestData.exportTarget()
        try await h.repository.insertTarget(target)

        async let first = h.service.export(targetId: target.id)
        async let second = h.service.export(targetId: target.id)
        let outcomes = await [first, second]
        #expect(outcomes == [.exported(fileId: "FILE1"), .exported(fileId: "FILE1")])
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "PATCH"])
        #expect(try await h.target(target.id).googleFileId == "FILE1")
    }

    @Test func exportRemembersContentHashUntilAFailure() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("FILE1"), .response(status: 404, body: "")])
        defer { TestSettings.remove(h.settings) }
        let target = TestData.exportTarget()
        try await h.repository.insertTarget(target)
        #expect(await h.service.lastExportedHash(targetId: target.id) == nil)

        #expect(await h.service.export(targetId: target.id) == .exported(fileId: "FILE1"))
        let hash = try #require(await h.service.renderedHash(targetId: target.id))
        #expect(hash.count == 64)
        #expect(await h.service.lastExportedHash(targetId: target.id) == hash)

        h.now.advance(by: 3600)
        #expect(await h.service.renderedHash(targetId: target.id) == hash)

        #expect(await h.service.export(targetId: target.id) == .docMissing)
        #expect(await h.service.lastExportedHash(targetId: target.id) == nil)
    }

    // MARK: Errors

    @Test func errorsUnauthorizedRefreshesOnce() async throws {
        let h = try await Harness(replies: [
            Self.about,
            .response(status: 401, body: ""),
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(await h.auth.forcedRefreshCount == 1)
        let requests = await h.http.requests
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer token", "Bearer token", "Bearer token-refreshed",
        ])

        let twice = try await Harness(replies: [
            Self.about,
            .response(status: 401, body: ""),
            .response(status: 401, body: ""),
        ])
        defer { TestSettings.remove(twice.settings) }
        let failed = await twice.service.exportScope(.all, options: ExportOptions())
        #expect(failed.outcome == .signInRequired)
        #expect(await twice.auth.forcedRefreshCount == 1)
        #expect(try await twice.target(failed.targetId).lastStatus == "signInRequired")
    }

    @Test func errorsSignInRequiredFromAuth() async throws {
        let h = try await Harness(replies: [], auth: StubGoogleAuth(error: .signInRequired))
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .signInRequired)
        #expect(try await h.target(result.targetId).lastStatus == "signInRequired")
        #expect(await h.http.requests.isEmpty)
    }

    @Test func errorsDocMissing() async throws {
        let h = try await Harness(replies: [
            Self.about,
            Self.ok("FILE1"),
            .response(status: 404, body: "gone"),
            Self.ok("FILE2"),
        ])
        defer { TestSettings.remove(h.settings) }
        let created = await h.service.exportScope(.all, options: ExportOptions())
        let id = try #require(created.targetId)

        #expect(await h.service.export(targetId: id) == .docMissing)
        let missing = try await h.target(id)
        #expect(missing.lastStatus == "docMissing")
        #expect(missing.googleFileId == "FILE1")

        try await h.repository.clearFileId(id: id)
        #expect(await h.service.export(targetId: id) == .exported(fileId: "FILE2"))
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "PATCH", "POST"])
        #expect(try await h.target(id).googleFileId == "FILE2")
        #expect(try await h.target(id).lastStatus == "ok")
    }

    @Test func errorsForbiddenUpdate() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("FILE1"), .response(status: 403, body: "")])
        defer { TestSettings.remove(h.settings) }
        let created = await h.service.exportScope(.all, options: ExportOptions())
        let id = try #require(created.targetId)
        #expect(await h.service.export(targetId: id) == .docMissing)
    }

    @Test func errorsCreateRefusedIsFailure() async throws {
        let h = try await Harness(replies: [Self.about, .response(status: 404, body: "")])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        guard case .failed = result.outcome else {
            Issue.record("Expected .failed, got \(result.outcome)")
            return
        }
        #expect(try await h.target(result.targetId).lastStatus == "failed")
    }

    @Test func errorsRateLimitBackoff() async throws {
        let h = try await Harness(replies: [
            Self.about,
            .response(status: 429, body: ""),
            .response(status: 503, body: ""),
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(await h.sleeper.durations == [.seconds(1), .seconds(4)])

        let busy = try await Harness(replies: [
            Self.about,
            .response(status: 429, body: ""),
            .response(status: 429, body: ""),
            .response(status: 500, body: ""),
            .response(status: 429, body: ""),
        ])
        defer { TestSettings.remove(busy.settings) }
        let failed = await busy.service.exportScope(.all, options: ExportOptions())
        #expect(failed.outcome == .failed("Google Drive is busy. Try again later."))
        #expect(await busy.sleeper.durations == [.seconds(1), .seconds(4), .seconds(16)])
        let target = try await busy.target(failed.targetId)
        #expect(target.lastStatus == "failed")
        #expect(target.lastError == "Google Drive is busy. Try again later.")
    }

    @Test func errorsOffline() async throws {
        let h = try await Harness(replies: [.failure(URLError(.notConnectedToInternet))])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .queued)
        #expect(try await h.target(result.targetId).lastStatus == "queued")
    }

    @Test func errorsOtherStatusDoesNotLeakBody() async throws {
        let h = try await Harness(replies: [Self.about, .response(status: 400, body: "secret body text")])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .failed("Google Drive returned an error (400)."))
        let target = try await h.target(result.targetId)
        #expect(target.lastError?.contains("secret") == false)
    }

    @Test func errorsNotConfigured() async throws {
        let h = try await Harness(replies: [], auth: StubGoogleAuth(configured: false))
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .notConfigured)
        #expect(result.targetId == nil)

        let target = TestData.exportTarget()
        try await h.repository.insertTarget(target)
        #expect(await h.service.export(targetId: target.id) == .notConfigured)
        #expect(try await h.target(target.id).lastStatus == "never")
        #expect(await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions()) == .notConfigured)
        #expect(await h.http.requests.isEmpty)
    }

    // MARK: Format, folder, selection

    @Test func htmlFallback() async throws {
        let h = try await Harness(replies: [
            .response(status: 200, body: Self.aboutNoMarkdown),
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        let body = try await h.body(1)
        #expect(body.contains("Content-Type: text/html; charset=UTF-8"))
        #expect(!body.contains("text/markdown"))
        #expect(body.contains("<h1>"))
        #expect(try await h.target(result.targetId).format == .html)
    }

    @Test func selectionCreatesNoTarget() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("SEL1")])
        defer { TestSettings.remove(h.settings) }
        let outcome = await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions())
        #expect(outcome == .exported(fileId: "SEL1"))
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST"])
        let body = try await h.body(1)
        #expect(body.contains(#""name":"StudyReader – Selection""#))
        #expect(body.contains("Mitochondria are the powerhouse"))
        #expect(try await h.repository.fetchTargets().isEmpty)
    }

    @Test func folderFromSettings() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        h.settings.googleExportFolderId = "FOLDER123"
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(try await h.body(1).contains(#""parents":["FOLDER123"]"#))
        #expect(try await h.target(result.targetId).googleFolderId == "FOLDER123")
    }

    @Test func aboutIsAskedOncePerAccount() async throws {
        let h = try await Harness(replies: [Self.about, Self.ok("FILE1"), Self.ok("SEL1")])
        defer { TestSettings.remove(h.settings) }
        _ = await h.service.exportScope(.all, options: ExportOptions())
        _ = await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions())
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST"])
    }
}
