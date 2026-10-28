import Foundation
import Testing
@testable import StudyReader

/// Throws as a cancelled sleep does.
private struct CancellingSleeper: Sleeper {
    func sleep(for duration: Duration) async throws {
        throw CancellationError()
    }
}

/// Returns at once and records the requested durations.
private actor RecordingSleeper: Sleeper {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }
}

/// Answers by method and path instead of a FIFO queue, so two concurrent export flows get the right reply whatever the
/// order they arrive in. The folder lookup finds nothing until a folder was created.
private actor RoutingHTTPClient: HTTPClient {
    private(set) var requests: [URLRequest] = []
    private(set) var folderCreates = 0
    private var uploads = 0

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path() ?? ""
        let body: String
        switch (method, path) {
        case ("GET", "/drive/v3/about"):
            body = #"{"importFormats":{"text/markdown":["application/vnd.google-apps.document"]}}"#
        case ("GET", "/drive/v3/files"):
            await Task.yield()
            body = folderCreates == 0 ? #"{"files":[]}"# : #"{"files":[{"id":"APPFOLDER"}]}"#
        case ("GET", "/drive/v3/files/APPFOLDER"):
            body = #"{"id":"APPFOLDER","mimeType":"application/vnd.google-apps.folder","trashed":false}"#
        case ("POST", "/drive/v3/files"):
            await Task.yield()
            folderCreates += 1
            body = #"{"id":"APPFOLDER"}"#
        case ("POST", "/upload/drive/v3/files"):
            uploads += 1
            body = #"{"id":"FILE\#(uploads)"}"#
        default:
            throw URLError(.resourceUnavailable)
        }
        guard let response = HTTPURLResponse(
            url: request.url ?? URL(filePath: "/"),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            throw URLError(.badServerResponse)
        }
        return (Data(body.utf8), response)
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

        init(
            replies: [StubHTTPClient.Reply],
            auth: StubGoogleAuth = StubGoogleAuth(),
            serviceSleeper: (any Sleeper)? = nil,
            seedFolder: Bool = true
        ) async throws {
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
            if seedFolder {
                settings.setGoogleAppFolderId("APPFOLDER", forAccount: "student@example.com")
            }
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
                sleeper: serviceSleeper ?? sleeper,
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
    private static let folderOK = StubHTTPClient.Reply.response(
        status: 200,
        body: #"{"id":"APPFOLDER","mimeType":"application/vnd.google-apps.folder","trashed":false}"#
    )

    // MARK: Create and update

    @Test func createThenUpdate() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.ok("FILE1"), Self.ok("FILE1")])
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
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        #expect(requests[0].url?.path() == "/drive/v3/about")
        #expect(requests[1].url?.path() == "/drive/v3/files/APPFOLDER")
        #expect(requests[2].url?.path() == "/upload/drive/v3/files")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let createBody = try await h.body(2)
        #expect(createBody.contains("# StudyReader – All highlights"))
        #expect(createBody.contains("Mitochondria are the powerhouse"))

        h.now.advance(by: 60)
        let second = await h.service.exportScope(.all, options: ExportOptions())
        #expect(second.targetId == first.targetId)
        #expect(second.outcome == .exported(fileId: "FILE1"))
        requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "PATCH"])
        #expect(requests[3].url?.path() == "/upload/drive/v3/files/FILE1")
        let updated = try await h.target(first.targetId)
        #expect(updated.googleFileId == "FILE1")
        #expect(updated.lastExportedAt == TestData.referenceDate.addingTimeInterval(60))
        #expect(try await h.repository.fetchTargets().count == 1)
    }

    // MARK: Serialization and content hash (T74)

    @Test func concurrentExportsOfOneTargetRunOneAfterAnother() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.ok("FILE1"), Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        let target = TestData.exportTarget()
        try await h.repository.insertTarget(target)

        async let first = h.service.export(targetId: target.id)
        async let second = h.service.export(targetId: target.id)
        let outcomes = await [first, second]
        #expect(outcomes == [.exported(fileId: "FILE1"), .exported(fileId: "FILE1")])
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "PATCH"])
        #expect(try await h.target(target.id).googleFileId == "FILE1")
    }

    @Test func exportRemembersContentHashUntilAFailure() async throws {
        let h = try await Harness(replies: [
            Self.about, Self.folderOK, Self.ok("FILE1"), .response(status: 404, body: ""),
        ])
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
            Self.folderOK,
            .response(status: 401, body: ""),
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(await h.auth.forcedRefreshCount == 1)
        let requests = await h.http.requests
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer token", "Bearer token", "Bearer token", "Bearer token-refreshed",
        ])

        let twice = try await Harness(replies: [
            Self.about,
            Self.folderOK,
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
            Self.folderOK,
            Self.ok("FILE1"),
            .response(status: 404, body: "gone"),
            Self.folderOK,
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
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "PATCH", "GET", "POST"])
        #expect(try await h.target(id).googleFileId == "FILE2")
        #expect(try await h.target(id).lastStatus == "ok")
    }

    @Test func errorsForbiddenUpdate() async throws {
        let h = try await Harness(replies: [
            Self.about, Self.folderOK, Self.ok("FILE1"), .response(status: 403, body: ""),
        ])
        defer { TestSettings.remove(h.settings) }
        let created = await h.service.exportScope(.all, options: ExportOptions())
        let id = try #require(created.targetId)
        #expect(await h.service.export(targetId: id) == .failed(Self.updateRefusedText))
        let target = try await h.target(id)
        #expect(target.lastStatus == "failed")
        #expect(target.googleFileId == "FILE1")
    }

    @Test func errorsCreateRefusedIsFailure() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, .response(status: 404, body: "")])
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
            Self.folderOK,
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
            Self.folderOK,
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

    // MARK: Drive 403 reasons (T94, M1)

    private static let storageFullText = "Your Google Drive storage is full. Free up space, then export again."
    private static let dailyLimitText = "Google Drive's daily limit for StudyReader is used up. Try again tomorrow."
    private static let noAccessText = "StudyReader can no longer write to this Google Doc. "
        + "Remove the export target and export again to make a new Doc."
    private static let updateRefusedText = "Google Drive refused the update. Try again later."
    private static let busyText = "Google Drive is busy. Try again later."

    private static func forbidden(_ reason: String) -> StubHTTPClient.Reply {
        .response(
            status: 403,
            body: #"{"error":{"errors":[{"domain":"usageLimits","reason":"\#(reason)"}],"code":403}}"#
        )
    }

    /// A saved target that already has a Doc, so the export is an update: requests are about, then PATCH.
    private static func updateHarness(_ patches: [StubHTTPClient.Reply]) async throws -> (Harness, String) {
        let h = try await Harness(replies: [about] + patches)
        var target = TestData.exportTarget()
        target.googleFileId = "FILE1"
        try await h.repository.insertTarget(target)
        return (h, target.id)
    }

    @Test func errors403StorageQuotaKeepsTheDocLink() async throws {
        let (h, id) = try await Self.updateHarness([Self.forbidden("storageQuotaExceeded")])
        defer { TestSettings.remove(h.settings) }
        #expect(await h.service.export(targetId: id) == .failed(Self.storageFullText))
        let target = try await h.target(id)
        #expect(target.lastStatus == "failed")
        #expect(target.lastError == Self.storageFullText)
        #expect(target.googleFileId == "FILE1")
        #expect(await h.sleeper.durations.isEmpty)
    }

    @Test func errors403UserRateLimitBacksOff() async throws {
        let (h, id) = try await Self.updateHarness([Self.forbidden("userRateLimitExceeded"), Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        #expect(await h.service.export(targetId: id) == .exported(fileId: "FILE1"))
        #expect(await h.sleeper.durations == [.seconds(1)])
        #expect(await h.http.requests.map(\.httpMethod) == ["GET", "PATCH", "PATCH"])
    }

    @Test func errors403RateLimitBacksOffThenFails() async throws {
        let rate = Self.forbidden("rateLimitExceeded")
        let (h, id) = try await Self.updateHarness([rate, rate, rate, rate])
        defer { TestSettings.remove(h.settings) }
        #expect(await h.service.export(targetId: id) == .failed(Self.busyText))
        #expect(await h.sleeper.durations == [.seconds(1), .seconds(4), .seconds(16)])
        let target = try await h.target(id)
        #expect(target.googleFileId == "FILE1")
        #expect(target.lastStatus == "failed")
    }

    @Test func errors403DailyLimitFailsWithoutBackoff() async throws {
        let (h, id) = try await Self.updateHarness([Self.forbidden("dailyLimitExceeded")])
        defer { TestSettings.remove(h.settings) }
        #expect(await h.service.export(targetId: id) == .failed(Self.dailyLimitText))
        #expect(await h.sleeper.durations.isEmpty)
        let target = try await h.target(id)
        #expect(target.lastStatus == "failed")
        #expect(target.googleFileId == "FILE1")
    }

    @Test func errors403NoAccessKeepsTheDocLink() async throws {
        for reason in ["appNotAuthorizedToFile", "insufficientFilePermissions"] {
            let (h, id) = try await Self.updateHarness([Self.forbidden(reason)])
            defer { TestSettings.remove(h.settings) }
            #expect(await h.service.export(targetId: id) == .failed(Self.noAccessText))
            let target = try await h.target(id)
            #expect(target.lastStatus == "failed")
            #expect(target.lastError == Self.noAccessText)
            #expect(target.googleFileId == "FILE1")
        }
    }

    @Test func errors403UnknownReasonFails() async throws {
        for reply in [StubHTTPClient.Reply.response(status: 403, body: ""), Self.forbidden("somethingNew")] {
            let (h, id) = try await Self.updateHarness([reply])
            defer { TestSettings.remove(h.settings) }
            #expect(await h.service.export(targetId: id) == .failed(Self.updateRefusedText))
            let target = try await h.target(id)
            #expect(target.lastStatus == "failed")
            #expect(target.googleFileId == "FILE1")
            #expect(await h.sleeper.durations.isEmpty)
        }
    }

    @Test func errorsTrashedDocIsDocMissing() async throws {
        let (h, id) = try await Self.updateHarness([.response(status: 200, body: #"{"id":"FILE1","trashed":true}"#)])
        defer { TestSettings.remove(h.settings) }
        #expect(await h.service.export(targetId: id) == .docMissing)
        let target = try await h.target(id)
        #expect(target.lastStatus == "docMissing")
        #expect(target.googleFileId == "FILE1")

        let (kept, keptId) = try await Self.updateHarness([
            .response(status: 200, body: #"{"id":"FILE1","trashed":false}"#),
        ])
        defer { TestSettings.remove(kept.settings) }
        #expect(await kept.service.export(targetId: keptId) == .exported(fileId: "FILE1"))
        #expect(try await kept.target(keptId).lastStatus == "ok")
    }

    @Test func updateRequestAsksForTheTrashedFlag() async throws {
        let (h, id) = try await Self.updateHarness([Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        _ = await h.service.export(targetId: id)
        let requests = await h.http.requests
        #expect(requests.last?.url?.query()?.contains("fields=id,modifiedTime,trashed") == true)
    }

    @Test func errors403OnCreateIsRefusedUpload() async throws {
        let refused = "Google Drive refused the upload."
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.forbidden("appNotAuthorizedToFile")])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .failed(refused))
        let target = try await h.target(result.targetId)
        #expect(target.lastStatus == "failed")
        #expect(target.googleFileId == nil)

        let storage = try await Harness(replies: [Self.about, Self.folderOK, Self.forbidden("storageQuotaExceeded")])
        defer { TestSettings.remove(storage.settings) }
        let full = await storage.service.exportScope(.all, options: ExportOptions())
        #expect(full.outcome == .failed(Self.storageFullText))
    }

    @Test func appFolderRateLimitBacksOff() async throws {
        let h = try await Harness(replies: [
            Self.about, Self.forbidden("userRateLimitExceeded"), Self.folderOK, Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(await h.sleeper.durations == [.seconds(1)])
        let paths = await h.http.requests.map { $0.url?.path() }
        #expect(paths == [
            "/drive/v3/about", "/drive/v3/files/APPFOLDER", "/drive/v3/files/APPFOLDER", "/upload/drive/v3/files",
        ])

        let full = try await Harness(replies: [Self.about, Self.forbidden("storageQuotaExceeded")])
        defer { TestSettings.remove(full.settings) }
        let failed = await full.service.exportScope(.all, options: ExportOptions())
        #expect(failed.outcome == .failed(Self.storageFullText))
        #expect(await full.http.requests.count == 2)
    }

    @Test func appFolderForbiddenWithoutLimitIsLookedUpAgain() async throws {
        let h = try await Harness(replies: [
            Self.about,
            Self.forbidden("insufficientFilePermissions"),
            .response(status: 200, body: #"{"files":[]}"#),
            Self.ok("NEWFOLDER"),
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(h.settings.googleAppFolderId(forAccount: "student@example.com") == "NEWFOLDER")
    }

    @Test func appFolderCreateForbiddenFails() async throws {
        let h = try await Harness(
            replies: [
                Self.about,
                .response(status: 200, body: #"{"files":[]}"#),
                Self.forbidden("somethingNew"),
            ],
            seedFolder: false
        )
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .failed("Couldn't use the StudyReader folder in Google Drive."))

        let daily = try await Harness(
            replies: [Self.about, .response(status: 200, body: #"{"files":[]}"#), Self.forbidden("dailyLimitExceeded")],
            seedFolder: false
        )
        defer { TestSettings.remove(daily.settings) }
        let limited = await daily.service.exportScope(.all, options: ExportOptions())
        #expect(limited.outcome == .failed(Self.dailyLimitText))
    }

    @Test func aboutForbiddenAssumesMarkdown() async throws {
        let h = try await Harness(replies: [Self.forbidden("somethingNew"), Self.folderOK, Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(try await h.body(2).contains("text/markdown"))
    }

    // MARK: Offline

    @Test func selectionOfflineDoesNotPromiseALaterRun() async throws {
        let h = try await Harness(replies: [.failure(URLError(.notConnectedToInternet))])
        defer { TestSettings.remove(h.settings) }
        let outcome = await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions())
        #expect(outcome == .failed("Couldn't reach Google Drive. Check your connection and try again."))
        #expect(!ExportSheetModel.message(for: outcome).contains("when you're back online"))
        #expect(try await h.repository.fetchTargets().isEmpty)
    }

    @Test func errorsOffline() async throws {
        let h = try await Harness(replies: [.failure(URLError(.notConnectedToInternet))])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .queued)
        #expect(try await h.target(result.targetId).lastStatus == "queued")
    }

    @Test func cancelledRequestRecordsNothing() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, .failure(URLError(.cancelled))])
        defer { TestSettings.remove(h.settings) }
        var seeded = TestData.exportTarget()
        seeded.googleFolderId = "FOLDER"
        try await h.repository.insertTarget(seeded)
        let before = try await h.target(seeded.id)

        #expect(await h.service.export(targetId: seeded.id) == .cancelled)
        let after = try await h.target(seeded.id)
        #expect(after.lastStatus == before.lastStatus)
        #expect(after.lastError == before.lastError)
        #expect(after.googleFileId == before.googleFileId)
        #expect(after == before)
        #expect(await h.service.lastExportedHash(targetId: seeded.id) == nil)
    }

    @Test func cancelledBackoffRecordsNothing() async throws {
        let h = try await Harness(
            replies: [Self.about, Self.folderOK, .response(status: 503, body: "")],
            serviceSleeper: CancellingSleeper()
        )
        defer { TestSettings.remove(h.settings) }
        let seeded = TestData.exportTarget()
        try await h.repository.insertTarget(seeded)
        let before = try await h.target(seeded.id)

        #expect(await h.service.export(targetId: seeded.id) == .cancelled)
        #expect(try await h.target(seeded.id) == before)
    }

    @Test func updateRefreshesTokenOnce401() async throws {
        let h = try await Harness(replies: [
            Self.about,
            .response(status: 401, body: ""),
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        var seeded = TestData.exportTarget()
        seeded.googleFileId = "FILE1"
        try await h.repository.insertTarget(seeded)

        #expect(await h.service.export(targetId: seeded.id) == .exported(fileId: "FILE1"))
        #expect(await h.auth.forcedRefreshCount == 1)
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "PATCH", "PATCH"])
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer token-refreshed")
    }

    @Test func errorsOtherStatusDoesNotLeakBody() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, .response(status: 400, body: "secret body text")])
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
            Self.folderOK,
            Self.ok("FILE1"),
        ])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        let body = try await h.body(2)
        #expect(body.contains("Content-Type: text/html; charset=UTF-8"))
        #expect(!body.contains("text/markdown"))
        #expect(body.contains("<h1>"))
        #expect(try await h.target(result.targetId).format == .html)
    }

    @Test func selectionCreatesNoTarget() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.ok("SEL1")])
        defer { TestSettings.remove(h.settings) }
        let outcome = await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions())
        #expect(outcome == .exported(fileId: "SEL1"))
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        let body = try await h.body(2)
        #expect(body.contains(#""name":"StudyReader – Selection""#))
        #expect(body.contains("Mitochondria are the powerhouse"))
        #expect(try await h.repository.fetchTargets().isEmpty)
    }

    // MARK: App folder (ADR-0018 amendment, T92a)

    private static let appFolderMime = "application/vnd.google-apps.folder"

    private func parents(_ body: String, contain ids: [String]) -> Bool {
        let list = ids.map { "\"\($0)\"" }.joined(separator: ",")
        return body.contains(#""parents":[\#(list)]"#)
    }

    @Test func appFolderCreatedOnFirstExport() async throws {
        let h = try await Harness(
            replies: [Self.about, .response(status: 200, body: #"{"files":[]}"#), Self.ok("APPFOLDER"), Self.ok("FILE1")],
            seedFolder: false
        )
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))

        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "POST"])
        #expect(requests.map { $0.url?.path() } == [
            "/drive/v3/about", "/drive/v3/files", "/drive/v3/files", "/upload/drive/v3/files",
        ])
        let lookup = try #require(requests[1].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(
            lookup.queryItems?.first { $0.name == "q" }?.value
                == "name = 'StudyReader' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        )
        #expect(try await h.body(2) == #"{"mimeType":"application/vnd.google-apps.folder","name":"StudyReader"}"#)
        #expect(parents(try await h.body(3), contain: ["APPFOLDER"]))
        #expect(h.settings.googleAppFolderId(forAccount: "student@example.com") == "APPFOLDER")
        #expect(try await h.target(result.targetId).googleFolderId == "APPFOLDER")
    }

    @Test func appFolderReusedFromAnEarlierExport() async throws {
        let h = try await Harness(
            replies: [
                Self.about,
                .response(status: 200, body: #"{"files":[{"id":"OLDFOLDER"}]}"#),
                Self.ok("FILE1"),
            ],
            seedFolder: false
        )
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))

        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        #expect(requests.map { $0.url?.path() } == ["/drive/v3/about", "/drive/v3/files", "/upload/drive/v3/files"])
        #expect(parents(try await h.body(2), contain: ["OLDFOLDER"]))
        #expect(h.settings.googleAppFolderId(forAccount: "student@example.com") == "OLDFOLDER")
    }

    @Test func appFolderStoredIdIsVerifiedAndReused() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))

        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        #expect(requests.map { $0.url?.path() } == [
            "/drive/v3/about", "/drive/v3/files/APPFOLDER", "/upload/drive/v3/files",
        ])
        #expect(requests[1].url?.query() == "fields=id,mimeType,trashed")
        #expect(parents(try await h.body(2), contain: ["APPFOLDER"]))
    }

    @Test func appFolderRecreatedWhenTrashed() async throws {
        let create = [
            StubHTTPClient.Reply.response(status: 200, body: #"{"files":[]}"#),
            Self.ok("NEWFOLDER"),
            Self.ok("FILE1"),
        ]
        let trashed = StubHTTPClient.Reply.response(
            status: 200,
            body: #"{"id":"APPFOLDER","mimeType":"\#(Self.appFolderMime)","trashed":true}"#
        )
        let h = try await Harness(replies: [Self.about, trashed] + create)
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(await h.http.requests.map(\.httpMethod) == ["GET", "GET", "GET", "POST", "POST"])
        #expect(parents(try await h.body(4), contain: ["NEWFOLDER"]))
        #expect(h.settings.googleAppFolderId(forAccount: "student@example.com") == "NEWFOLDER")

        let gone = try await Harness(replies: [Self.about, .response(status: 404, body: "")] + create)
        defer { TestSettings.remove(gone.settings) }
        let again = await gone.service.exportScope(.all, options: ExportOptions())
        #expect(again.outcome == .exported(fileId: "FILE1"))
        #expect(await gone.http.requests.map(\.httpMethod) == ["GET", "GET", "GET", "POST", "POST"])
        #expect(parents(try await gone.body(4), contain: ["NEWFOLDER"]))
        #expect(gone.settings.googleAppFolderId(forAccount: "student@example.com") == "NEWFOLDER")
    }

    @Test func appFolderMovedStillWorks() async throws {
        let moved = StubHTTPClient.Reply.response(
            status: 200,
            body: #"{"id":"APPFOLDER","mimeType":"\#(Self.appFolderMime)","trashed":false,"parents":["SOMEWHERE"]}"#
        )
        let h = try await Harness(replies: [Self.about, moved, Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .exported(fileId: "FILE1"))
        #expect(await h.http.requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        #expect(parents(try await h.body(2), contain: ["APPFOLDER"]))
        #expect(h.settings.googleAppFolderId(forAccount: "student@example.com") == "APPFOLDER")
    }

    @Test func appFolderConcurrentFirstExportsCreateOneFolder() async throws {
        let h = try await Harness(replies: [], seedFolder: false)
        defer { TestSettings.remove(h.settings) }
        let http = RoutingHTTPClient()
        let service = GoogleExportService(
            auth: StubGoogleAuth(),
            http: http,
            repository: h.repository,
            settings: h.settings,
            now: h.now,
            sleeper: h.sleeper,
            timeZone: TimeZone(identifier: "UTC") ?? .gmt,
            colorLabels: { ["Yellow", "Green", "Blue", "Pink", "Purple"] }
        )

        async let first = service.exportScope(.all, options: ExportOptions())
        async let second = service.exportScope(.document(Self.docId), options: ExportOptions())
        let results = await [first, second]
        for result in results {
            guard case .exported = result.outcome else {
                Issue.record("Expected .exported, got \(result.outcome)")
                return
            }
        }

        #expect(await http.folderCreates == 1)
        let requests = await http.requests
        let uploads = requests.filter { $0.url?.path() == "/upload/drive/v3/files" }
        #expect(uploads.count == 2)
        for upload in uploads {
            #expect(parents(String(decoding: upload.httpBody ?? Data(), as: UTF8.self), contain: ["APPFOLDER"]))
        }
        #expect(h.settings.googleAppFolderId(forAccount: "student@example.com") == "APPFOLDER")
    }

    @Test func appFolderIsPerAccount() async throws {
        let h = try await Harness(
            replies: [
                Self.about,
                .response(status: 200, body: #"{"id":"FOLDER_A","mimeType":"\#(Self.appFolderMime)"}"#),
                Self.ok("FILE_A"),
            ],
            auth: StubGoogleAuth(email: "a@example.com"),
            seedFolder: false
        )
        defer { TestSettings.remove(h.settings) }
        h.settings.setGoogleAppFolderId("FOLDER_A", forAccount: "a@example.com")

        let httpB = StubHTTPClient([
            Self.about,
            .response(status: 200, body: #"{"files":[]}"#),
            Self.ok("FOLDER_B"),
            Self.ok("FILE_B"),
        ])
        let serviceB = GoogleExportService(
            auth: StubGoogleAuth(email: "b@example.com"),
            http: httpB,
            repository: h.repository,
            settings: h.settings,
            now: h.now,
            sleeper: h.sleeper,
            timeZone: TimeZone(identifier: "UTC") ?? .gmt,
            colorLabels: { ["Yellow", "Green", "Blue", "Pink", "Purple"] }
        )

        let resultB = await serviceB.exportScope(.all, options: ExportOptions())
        #expect(resultB.outcome == .exported(fileId: "FILE_B"))
        let uploadB = try #require(await httpB.requests.last)
        #expect(parents(String(decoding: uploadB.httpBody ?? Data(), as: UTF8.self), contain: ["FOLDER_B"]))

        let resultA = await h.service.exportScope(.document(Self.docId), options: ExportOptions())
        #expect(resultA.outcome == .exported(fileId: "FILE_A"))
        #expect(parents(try await h.body(2), contain: ["FOLDER_A"]))

        #expect(h.settings.googleAppFolderId(forAccount: "a@example.com") == "FOLDER_A")
        #expect(h.settings.googleAppFolderId(forAccount: "b@example.com") == "FOLDER_B")
    }

    @Test func appFolderOldSettingsAreIgnored() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.ok("FILE1")])
        defer { TestSettings.remove(h.settings) }
        h.settings.defaults.set("PASTED123", forKey: "settings.googleExportFolderId")
        var seeded = TestData.exportTarget()
        seeded.googleFolderId = "OLDFOLDER"
        try await h.repository.insertTarget(seeded)

        #expect(await h.service.export(targetId: seeded.id) == .exported(fileId: "FILE1"))
        let body = try await h.body(2)
        #expect(parents(body, contain: ["APPFOLDER"]))
        #expect(!body.contains("PASTED123"))
        #expect(!body.contains("OLDFOLDER"))
        #expect(try await h.target(seeded.id).googleFolderId == "APPFOLDER")
    }

    @Test func appFolderSelectionUsesTheFolder() async throws {
        let h = try await Harness(replies: [Self.about, Self.folderOK, Self.ok("SEL1")])
        defer { TestSettings.remove(h.settings) }
        let outcome = await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions())
        #expect(outcome == .exported(fileId: "SEL1"))
        let requests = await h.http.requests
        #expect(requests.map { $0.url?.path() } == [
            "/drive/v3/about", "/drive/v3/files/APPFOLDER", "/upload/drive/v3/files",
        ])
        #expect(parents(try await h.body(2), contain: ["APPFOLDER"]))
        #expect(try await h.repository.fetchTargets().isEmpty)
    }

    @Test func appFolderLookupRefusedFails() async throws {
        let h = try await Harness(replies: [Self.about, .response(status: 403, body: "")], seedFolder: false)
        defer { TestSettings.remove(h.settings) }
        let result = await h.service.exportScope(.all, options: ExportOptions())
        #expect(result.outcome == .failed("Couldn't use the StudyReader folder in Google Drive."))
        let requests = await h.http.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path() != "/upload/drive/v3/files" })
        #expect(try await h.target(result.targetId).lastStatus == "failed")
    }
    @Test func aboutIsAskedOncePerAccount() async throws {
        let h = try await Harness(replies: [
            Self.about, Self.folderOK, Self.ok("FILE1"), Self.folderOK, Self.ok("SEL1"),
        ])
        defer { TestSettings.remove(h.settings) }
        _ = await h.service.exportScope(.all, options: ExportOptions())
        _ = await h.service.exportSelection(highlightIds: [Self.highlightId], options: ExportOptions())
        let requests = await h.http.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "GET", "POST"])
    }
}
