import Foundation
import Markdown

/// Result of one export attempt. `failed` carries a short user-facing text, never a response body.
enum ExportOutcome: Equatable, Sendable {
    case exported(fileId: String)
    /// Offline; T74 retries.
    case queued
    case signInRequired
    /// 403/404 on update.
    case docMissing
    case notConfigured
    /// The request or a backoff wait was cancelled. Nothing is written to the target.
    case cancelled
    case failed(String)
}

/// Uploads rendered Markdown to Google Drive as a Google Doc (ARCHITECTURE §9.2, ADR-0007, ADR-0018).
/// Every new Doc (first export, Create New Doc, Export Selection) goes into a folder named "StudyReader" that the app
/// creates in My Drive on the first export, remembers per Google account and reuses (ADR-0018 amendment, app folder):
/// under `drive.file` the app can only use folders it created itself.
/// Network and sign-in sit behind `HTTPClient` and `GoogleAuthProviding`; waiting goes through `Sleeper`.
/// Logs target ids and HTTP status codes only: never tokens, emails, titles or document content.
actor GoogleExportService {
    static let backoff: [Duration] = [.seconds(1), .seconds(4), .seconds(16)]

    private static let log = Log.logger("export")
    private static let busyText = "Google Drive is busy. Try again later."
    private static let folderRefusedText = "Couldn't use the StudyReader folder in Google Drive."
    private static let unexpectedResponseText = "Google Drive returned an unexpected response."

    /// Gate key of the app-folder resolution. Not a UUID, so it can't collide with a target id.
    private static let folderGateKey = "#app-folder"

    private let auth: any GoogleAuthProviding
    private let http: any HTTPClient
    private let repository: ExportRepository
    private let settings: SettingsStore
    private let now: any Now
    private let sleeper: any Sleeper
    private let timeZone: TimeZone
    private let colorLabels: @Sendable () -> [String]

    /// Signed-in account (email, "" when unknown) → whether Drive imports Markdown. In memory only.
    private var markdownImport: [String: Bool] = [:]

    /// Target id → `contentHash` of the Markdown uploaded by its last export, only while that export succeeded.
    /// In memory only: a new process starts empty.
    private var exportedHashes: [String: String] = [:]

    /// Targets with an export running, and the exports waiting for them (one gate per target, FIFO). The reserved key
    /// `folderGateKey` serializes the app-folder resolution of all exports. Lock order: target gate, then folder gate.
    private var busyTargets: Set<String> = []
    private var gateWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// The date the content hash is rendered with, so the "_Exported <time>_" line never changes the hash.
    private static let hashDate = Date(timeIntervalSince1970: 0)

    init(
        auth: any GoogleAuthProviding,
        http: any HTTPClient,
        repository: ExportRepository,
        settings: SettingsStore,
        now: any Now,
        sleeper: any Sleeper,
        timeZone: TimeZone = .current,
        colorLabels: @escaping @Sendable () -> [String]
    ) {
        self.auth = auth
        self.http = http
        self.repository = repository
        self.settings = settings
        self.now = now
        self.sleeper = sleeper
        self.timeZone = timeZone
        self.colorLabels = colorLabels
    }

    // MARK: Public

    /// Renders the target's scope with its options and uploads: create when `googleFileId` is nil, else update.
    /// Records the outcome on the target (status and error; on success also file ID, folder, format, export time).
    /// Exports of one target never overlap: a second call waits for the first, then runs (and updates the Doc the
    /// first one created). Different targets run concurrently.
    func export(targetId: String) async -> ExportOutcome {
        await acquireGate(for: targetId)
        defer { releaseGate(for: targetId) }
        return await performExport(targetId: targetId)
    }

    /// SHA-256 (hex) of the Markdown `export(targetId:)` would upload now, with the export time held constant. Reads
    /// the database only. nil when the target or its content can't be read.
    func renderedHash(targetId: String) async -> String? {
        do {
            guard let target = try await repository.fetchTarget(id: targetId) else { return nil }
            let content = try await repository.content(for: target.scope)
            return contentHash(content, options: target.options)
        } catch {
            return nil
        }
    }

    /// `renderedHash` of the last successful export of this target in this app run. nil before the first one and
    /// after any export that didn't succeed.
    func lastExportedHash(targetId: String) -> String? {
        exportedHashes[targetId]
    }

    private func performExport(targetId: String) async -> ExportOutcome {
        guard await auth.isConfigured else { return .notConfigured }
        let target: ExportTarget
        do {
            guard let found = try await repository.fetchTarget(id: targetId) else {
                return .failed("This export no longer exists.")
            }
            target = found
        } catch {
            return .failed("Couldn't read the export settings.")
        }

        let markdown: String
        let hash: String
        do {
            let content = try await repository.content(for: target.scope)
            markdown = renderMarkdown(content, options: target.options)
            hash = contentHash(content, options: target.options)
        } catch {
            return await finish(targetId: targetId, outcome: .failed("Couldn't prepare the export."), upload: nil, folderId: nil)
        }

        let result = await upload(
            title: target.title,
            markdown: markdown,
            fileId: target.googleFileId,
            logId: targetId
        )
        switch result {
        case .success(let success):
            return await finish(
                targetId: targetId,
                outcome: .exported(fileId: success.fileId),
                upload: success,
                folderId: success.folderId,
                contentHash: hash
            )
        case .failure(let outcome):
            return await finish(targetId: targetId, outcome: outcome, upload: nil, folderId: nil)
        }
    }

    /// Finds the target for `scope` (or inserts one: title "StudyReader – <scope name>", no folder yet: a new Doc goes
    /// into the app folder, ADR-0018 amendment), saves `options`, then `export(targetId:)`. Returns the target id too;
    /// nil when nothing was saved.
    func exportScope(
        _ scope: ExportScope,
        options: ExportOptions
    ) async -> (targetId: String?, outcome: ExportOutcome) {
        guard await auth.isConfigured else { return (nil, .notConfigured) }
        do {
            let title = Self.title(scopeName: try await repository.scopeName(for: scope))
            let id: String
            if let existing = try await repository.target(for: scope) {
                try await repository.updateOptions(id: existing.id, options: options, title: title)
                id = existing.id
            } else {
                let target = ExportTarget(
                    id: UUID().uuidString,
                    title: title,
                    scope: scope,
                    options: options,
                    googleFolderId: nil,
                    createdAt: now()
                )
                try await repository.insertTarget(target)
                id = target.id
            }
            return (id, await export(targetId: id))
        } catch {
            return (nil, .failed("Couldn't prepare the export."))
        }
    }

    /// One-off Doc from a selection, created in the app folder; always creates a new Doc and saves no target (ADR-0018).
    func exportSelection(highlightIds: [String], options: ExportOptions) async -> ExportOutcome {
        guard await auth.isConfigured else { return .notConfigured }
        guard !highlightIds.isEmpty else { return .failed("No highlights selected.") }
        let scopeName = "Selection"
        let markdown: String
        do {
            let content = try await repository.content(forHighlightIds: highlightIds, scopeName: scopeName)
            markdown = renderMarkdown(content, options: options)
        } catch {
            return .failed("Couldn't prepare the export.")
        }
        let result = await upload(
            title: Self.title(scopeName: scopeName),
            markdown: markdown,
            fileId: nil,
            logId: "selection"
        )
        switch result {
        case .success(let success):
            Self.log.info("Selection export finished")
            return .exported(fileId: success.fileId)
        case .failure(let outcome):
            return outcome
        }
    }

    // MARK: Upload

    private struct UploadSuccess {
        var fileId: String
        var format: ExportFormat
        /// The app folder a new Doc went into; nil for an update.
        var folderId: String?
    }

    private enum UploadResult {
        case success(UploadSuccess)
        case failure(ExportOutcome)
    }

    private enum Reply {
        case success(Data)
        /// 403 or 404.
        case denied
        case failure(ExportOutcome)
    }

    private enum FormatCheck {
        case supported(Bool)
        case failure(ExportOutcome)
    }

    private struct FileResponse: Decodable {
        var id: String?
    }

    private struct AboutResponse: Decodable {
        var importFormats: [String: [String]]?
    }

    private struct FolderResponse: Decodable {
        var mimeType: String?
        var trashed: Bool?
    }

    private struct FolderListResponse: Decodable {
        struct Item: Decodable {
            var id: String?
        }

        var files: [Item]?
    }

    private enum FolderResolution {
        case folder(String)
        case failure(ExportOutcome)
    }

    private func upload(
        title: String,
        markdown: String,
        fileId: String?,
        logId: String
    ) async -> UploadResult {
        var token: String
        do {
            token = try await auth.accessToken(forceRefresh: false)
        } catch {
            return .failure(Self.outcome(forAuthError: error))
        }

        let format: ExportFormat
        switch await importsMarkdown(token: &token, logId: logId) {
        case .supported(let supported):
            format = supported ? .markdown : .html
        case .failure(let outcome):
            return .failure(outcome)
        }
        let content = format == .html ? Self.html(from: markdown) : markdown

        var folderId: String?
        if fileId == nil {
            switch await resolveAppFolder(token: &token, logId: logId) {
            case .folder(let id):
                folderId = id
            case .failure(let outcome):
                return .failure(outcome)
            }
        }

        let reply = await send(token: &token, logId: logId) { accessToken in
            try DriveUploadRequest.make(
                fileId: fileId,
                title: title,
                folderId: folderId,
                format: format,
                content: content,
                accessToken: accessToken
            )
        }
        switch reply {
        case .success(let data):
            let returnedId = (try? JSONDecoder().decode(FileResponse.self, from: data))?.id
            guard let resolved = returnedId ?? fileId else {
                return .failure(.failed(Self.unexpectedResponseText))
            }
            return .success(UploadSuccess(fileId: resolved, format: format, folderId: folderId))
        case .denied:
            return .failure(fileId == nil ? .failed("Google Drive refused the upload.") : .docMissing)
        case .failure(let outcome):
            return .failure(outcome)
        }
    }

    /// Asks Drive once per account whether it converts Markdown to Docs. When the answer can't be read (the
    /// request is refused or the body is unexpected) Markdown is assumed and nothing is cached.
    private func importsMarkdown(token: inout String, logId: String) async -> FormatCheck {
        let account = await auth.currentEmail() ?? ""
        if let cached = markdownImport[account] { return .supported(cached) }

        let reply = await send(token: &token, logId: logId) { accessToken in
            try DriveUploadRequest.importFormats(accessToken: accessToken)
        }
        switch reply {
        case .success(let data):
            guard let formats = (try? JSONDecoder().decode(AboutResponse.self, from: data))?.importFormats else {
                return .supported(true)
            }
            let supported = formats["text/markdown"]?.contains(DriveUploadRequest.documentMimeType) ?? false
            markdownImport[account] = supported
            return .supported(supported)
        case .denied:
            return .supported(true)
        case .failure(let outcome):
            return .failure(outcome)
        }
    }

    /// The ID of the "StudyReader" folder to create a Doc in (ADR-0018 amendment). Runs behind the folder gate, so
    /// concurrent first exports make one folder: the second one re-reads the stored ID after it gets the gate.
    /// 1. A stored ID for the account is checked with `files.get`. A folder that isn't trashed is used, wherever it was
    ///    moved to (IDs survive moves). A deleted (404), trashed or non-folder item is forgotten and step 2 runs.
    /// 2. Look for the oldest app-visible, not trashed folder named "StudyReader" (a reinstall or a second Mac finds
    ///    the one folder). `drive.file` lists only what the app created, so a hand-made folder is never found.
    /// 3. Otherwise create it in My Drive.
    /// The result is stored for the account. A pasted folder ID from older builds is never used.
    /// Logs only which case happened, never an ID or the email.
    private func resolveAppFolder(token: inout String, logId: String) async -> FolderResolution {
        await acquireGate(for: Self.folderGateKey)
        defer { releaseGate(for: Self.folderGateKey) }

        let account = await auth.currentEmail() ?? ""
        var recreated = false
        if let stored = settings.googleAppFolderId(forAccount: account) {
            let reply = await send(token: &token, logId: logId) { accessToken in
                try DriveUploadRequest.folder(id: stored, accessToken: accessToken)
            }
            switch reply {
            case .success(let data):
                let info = try? JSONDecoder().decode(FolderResponse.self, from: data)
                if info?.mimeType == DriveUploadRequest.folderMimeType, info?.trashed != true {
                    Self.log.info("App folder reused for \(logId, privacy: .public)")
                    return .folder(stored)
                }
            case .denied:
                break
            case .failure(let outcome):
                return .failure(outcome)
            }
            settings.setGoogleAppFolderId(nil, forAccount: account)
            recreated = true
        }

        let listReply = await send(token: &token, logId: logId) { accessToken in
            try DriveUploadRequest.findAppFolder(accessToken: accessToken)
        }
        switch listReply {
        case .success(let data):
            let found = (try? JSONDecoder().decode(FolderListResponse.self, from: data))?.files?.first?.id
            if let found, !found.isEmpty {
                settings.setGoogleAppFolderId(found, forAccount: account)
                Self.log.info("App folder reused for \(logId, privacy: .public)")
                return .folder(found)
            }
        case .denied:
            return .failure(.failed(Self.folderRefusedText))
        case .failure(let outcome):
            return .failure(outcome)
        }

        let createReply = await send(token: &token, logId: logId) { accessToken in
            try DriveUploadRequest.createAppFolder(accessToken: accessToken)
        }
        switch createReply {
        case .success(let data):
            guard let created = (try? JSONDecoder().decode(FileResponse.self, from: data))?.id, !created.isEmpty else {
                return .failure(.failed(Self.unexpectedResponseText))
            }
            settings.setGoogleAppFolderId(created, forAccount: account)
            let what = recreated ? "recreated" : "created"
            Self.log.info("App folder \(what, privacy: .public) for \(logId, privacy: .public)")
            return .folder(created)
        case .denied:
            return .failure(.failed(Self.folderRefusedText))
        case .failure(let outcome):
            return .failure(outcome)
        }
    }

    /// Sends the request built by `build`. 401: refresh the token once and retry, then `.signInRequired`.
    /// 429 and 5xx: wait `backoff[i]` through the sleeper and retry, at most `backoff.count` times.
    private func send(
        token: inout String,
        logId: String,
        build: (String) throws -> URLRequest
    ) async -> Reply {
        var retries = 0
        var refreshed = false
        while true {
            let request: URLRequest
            do {
                request = try build(token)
            } catch {
                return .failure(.failed("Couldn't build the upload request."))
            }

            let status: Int
            let data: Data
            do {
                let (body, response) = try await http.send(request)
                data = body
                status = response.statusCode
            } catch {
                Self.log.info("Drive request failed before a response for \(logId, privacy: .public)")
                return .failure(Self.outcome(forTransportError: error))
            }
            Self.log.info("Drive answered \(status, privacy: .public) for \(logId, privacy: .public)")

            switch status {
            case 200..<300:
                return .success(data)
            case 401:
                if refreshed { return .failure(.signInRequired) }
                refreshed = true
                do {
                    token = try await auth.accessToken(forceRefresh: true)
                } catch {
                    return .failure(Self.outcome(forAuthError: error))
                }
            case 403, 404:
                return .denied
            case 429, 500..<600:
                guard retries < Self.backoff.count else { return .failure(.failed(Self.busyText)) }
                do {
                    try await sleeper.sleep(for: Self.backoff[retries])
                } catch {
                    return .failure(.cancelled)
                }
                retries += 1
            default:
                return .failure(.failed("Google Drive returned an error (\(status))."))
            }
        }
    }

    // MARK: Recording

    /// Stores the outcome on the target and returns it. `notConfigured` and `cancelled` change nothing. A success
    /// remembers `contentHash`; any other outcome forgets the remembered hash, so the next sync uploads again.
    private func finish(
        targetId: String,
        outcome: ExportOutcome,
        upload: UploadSuccess?,
        folderId: String?,
        contentHash: String? = nil
    ) async -> ExportOutcome {
        if case .exported = outcome {
            exportedHashes[targetId] = contentHash
        } else if outcome != .notConfigured, outcome != .cancelled {
            exportedHashes[targetId] = nil
        }
        let status: ExportStatus
        let message: String?
        switch outcome {
        case .exported:
            status = .ok
            message = nil
        case .queued:
            status = .queued
            message = "Offline. The export will retry when you're back online."
        case .signInRequired:
            status = .signInRequired
            message = "Sign in to Google to export."
        case .docMissing:
            status = .docMissing
            message = "The Google Doc is missing or you no longer have access to it."
        case .notConfigured, .cancelled:
            return outcome
        case .failed(let text):
            status = .failed
            message = text
        }
        do {
            try await repository.recordResult(
                id: targetId,
                status: status,
                error: message,
                fileId: upload?.fileId,
                folderId: upload == nil ? nil : folderId,
                format: upload?.format,
                exportedAt: upload == nil ? nil : now()
            )
        } catch {
            Self.log.error("Couldn't record the export result for \(targetId, privacy: .public)")
        }
        Self.log.info("Export of \(targetId, privacy: .public) finished: \(status.rawValue, privacy: .public)")
        return outcome
    }

    // MARK: Helpers

    /// A caller cancelled while waiting for the gate still runs its export once the gate is handed to it: the
    /// continuation isn't cancellable, and the export's own requests then end as `.cancelled`.
    private func acquireGate(for targetId: String) async {
        guard busyTargets.contains(targetId) else {
            busyTargets.insert(targetId)
            return
        }
        await withCheckedContinuation { continuation in
            gateWaiters[targetId, default: []].append(continuation)
        }
    }

    /// Hands the gate to the next waiting export, or frees it.
    private func releaseGate(for targetId: String) {
        guard var waiting = gateWaiters[targetId], !waiting.isEmpty else {
            busyTargets.remove(targetId)
            return
        }
        let next = waiting.removeFirst()
        gateWaiters[targetId] = waiting.isEmpty ? nil : waiting
        next.resume()
    }

    private func contentHash(_ content: ExportContent, options: ExportOptions) -> String {
        let markdown = ExportRenderer.render(
            content,
            options: options,
            colorLabels: colorLabels(),
            generatedAt: Self.hashDate,
            timeZone: timeZone
        )
        return Hashing.sha256Hex(of: markdown)
    }

    private func renderMarkdown(_ content: ExportContent, options: ExportOptions) -> String {
        ExportRenderer.render(
            content,
            options: options,
            colorLabels: colorLabels(),
            generatedAt: now(),
            timeZone: timeZone
        )
    }

    private static func title(scopeName: String) -> String {
        "StudyReader – \(scopeName)"
    }

    private static func html(from markdown: String) -> String {
        "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body>\n"
            + HTMLFormatter.format(Document(parsing: markdown))
            + "</body></html>\n"
    }

    private static func isOffline(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func outcome(forTransportError error: any Error) -> ExportOutcome {
        if isCancellation(error) { return .cancelled }
        return isOffline(error) ? .queued : .failed("Couldn't reach Google Drive.")
    }

    private static func outcome(forAuthError error: any Error) -> ExportOutcome {
        if isOffline(error) { return .queued }
        switch error as? GoogleAuthError {
        case .notConfigured:
            return .notConfigured
        case .signInRequired, .cancelled:
            return .signInRequired
        case nil:
            return .failed("Couldn't sign in to Google.")
        }
    }
}
