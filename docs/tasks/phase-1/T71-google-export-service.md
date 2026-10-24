# T71: GoogleExportService (Drive create/update, errors, HTML fallback)

- **Phase:** 1 (E1.8: F-21 upload)
- **Agent:** integrations
- **Depends on:** T70
- **ADRs:** docs/decisions/0007-google-export-drive-conversion.md, docs/decisions/0018-google-export-seams-and-status.md (read in full), docs/decisions/0015-settings-and-injected-sleep.md (Sleeper), ARCHITECTURE §9.2
- **Visual check needed:** no (no Google account needed; everything is tested with stubs)
- **References:** none. Don't read `Secrets/`.

## Goal
Upload rendered Markdown to Google Drive as a Google Doc: the first export creates the Doc and stores its file ID on the target; re-exports replace the content of the same file ID (so the Gemini Notebook source stays linked); handle 401, 403/404, 429/5xx and offline as specified; fall back to HTML when the account can't import Markdown. The network and Google sign-in sit behind protocols.

## Files to touch
- `StudyReader/Core/Support/HTTPClient.swift` (new: protocol + `URLSessionHTTPClient`)
- `StudyReader/Features/Export/GoogleAuthProviding.swift` (new: protocol + errors)
- `StudyReader/Features/Export/DriveUploadRequest.swift` (new: multipart request building)
- `StudyReader/Features/Export/GoogleExportService.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `httpClient`, `googleAuth`, `googleExportService`)
- `StudyReaderTests/Support/StubHTTPClient.swift`, `StudyReaderTests/Support/StubGoogleAuth.swift` (new)
- `StudyReaderTests/ExportTests/GoogleExportServiceTests.swift`, `DriveUploadRequestTests.swift` (new)

## Configuration (ADR-0018)
Google credentials are set up by the user (`Secrets/Google.xcconfig`, included by `Config/Base.xcconfig`). **Never read or print anything in `Secrets/`.** The app only sees the build settings `GOOGLE_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` through Info.plist (`GIDClientID`, URL scheme). When `GOOGLE_CLIENT_ID` is empty at runtime (`GIDClientID` empty or containing `$(`), `GoogleAuthProviding.isConfigured` is false, this service returns `.notConfigured` without any request, and the UI (T72, T73) shows "Google export not configured". Signing and the keychain entitlement are already configured by the user (ADR-0011); this task doesn't touch `project.yml` or entitlements.

## Interfaces to produce
```swift
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
struct URLSessionHTTPClient: HTTPClient {
    init(session: URLSession = URLSession(configuration: .ephemeral))   // never URLSession.shared
}

enum GoogleAuthError: Error, Equatable { case notConfigured, signInRequired, cancelled }
protocol GoogleAuthProviding: Sendable {
    var isConfigured: Bool { get async }
    func currentEmail() async -> String?
    /// A fresh access token for the drive.file scope; forceRefresh after a 401. Throws GoogleAuthError.
    func accessToken(forceRefresh: Bool) async throws -> String
}
/// Placeholder used until T72 provides GoogleSignInAuth: isConfigured false, every call throws .notConfigured.
struct UnconfiguredGoogleAuth: GoogleAuthProviding

enum ExportOutcome: Equatable, Sendable {
    case exported(fileId: String)
    case queued              // offline; T74 retries
    case signInRequired
    case docMissing          // 403/404 on update
    case notConfigured
    case failed(String)      // user-facing short text, e.g. "Google Drive returned an error (500)."
}

actor GoogleExportService {
    static let backoff: [Duration] = [.seconds(1), .seconds(4), .seconds(16)]
    init(auth: any GoogleAuthProviding, http: any HTTPClient, repository: ExportRepository,
         settings: SettingsStore, now: any Now, sleeper: any Sleeper, timeZone: TimeZone = .current,
         colorLabels: @escaping @Sendable () -> [String])
    /// Renders the target's scope with its options and uploads: create when googleFileId is nil, else update.
    /// Records the outcome on the target (ExportStatus + lastError; on success fileId, folderId, format, exportedAt).
    func export(targetId: String) async -> ExportOutcome
    /// Finds the target for scope (or inserts one: title "StudyReader – <scopeName>", folder =
    /// settings.googleExportFolderId), saves options, then export(targetId:). Returns the target id too.
    func exportScope(_ scope: ExportScope, options: ExportOptions) async -> (targetId: String?, outcome: ExportOutcome)
    /// One-off Doc from a selection; no target saved (ADR-0018, confirmed Q3). Title "StudyReader – Selection".
    func exportSelection(highlightIds: [String], options: ExportOptions) async -> ExportOutcome
}
```
Requests (ARCHITECTURE §9.2):
- Create: `POST https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink`.
- Update: `PATCH https://www.googleapis.com/upload/drive/v3/files/{fileId}?uploadType=multipart&fields=id,modifiedTime`.
- Headers: `Authorization: Bearer <token>`, `Content-Type: multipart/related; boundary=<boundary>`.
- Body (CRLF line endings): `--<b>`, `Content-Type: application/json; charset=UTF-8`, blank, metadata JSON; `--<b>`, `Content-Type: text/markdown; charset=UTF-8` (or `text/html; charset=UTF-8`), blank, content; `--<b>--`.
- Metadata: create `{"name": title, "mimeType": "application/vnd.google-apps.document"}` plus `"parents": [folderId]` when a folder is set; update `{"name": title}`. Encode with `JSONEncoder` (sorted keys) so tests can compare.
- `DriveUploadRequest.make(...)` builds the `URLRequest`; the boundary is injectable for tests (`"studyreader-boundary"`).
- Format check: once per signed-in email (keep `[email: Bool]` in memory and the result in the target's `format`): `GET https://www.googleapis.com/drive/v3/about?fields=importFormats`; Markdown is supported when `importFormats["text/markdown"]` contains `application/vnd.google-apps.document`. If not, upload HTML: `HTMLFormatter.format(markdown)` (swift-markdown) and record `format = .html`.

Errors:
- `auth.isConfigured == false` → `.notConfigured` (no request; status not changed).
- `accessToken` throws `.signInRequired` → `.signInRequired` (status `signInRequired`).
- HTTP 401 → `accessToken(forceRefresh: true)` and retry once; second 401 → `.signInRequired`.
- 403 or 404 on update → `.docMissing` (status `docMissing`, file ID kept until the user picks "Create new Doc" → `clearFileId`). On create, 403/404 → `.failed`.
- 429 or 5xx → wait `backoff[i]` through `sleeper` and retry, up to 3 retries; then `.failed("Google Drive is busy. Try again later.")`.
- `URLError` `.notConnectedToInternet`, `.networkConnectionLost`, `.dataNotAllowed`, `.cannotFindHost` → `.queued` (status `queued`).
- Other errors → `.failed(...)` with a short generic text (never the response body).
- Logging: target id, HTTP status code, outcome case. Never tokens, emails, titles or content.

## Tests
`DriveUploadRequestTests`: exact URL, method, headers and body for create (with and without folder) and update, Markdown and HTML.
`GoogleExportServiceTests` (in-memory environment; `StubHTTPClient` = actor with a queue of canned `(status, body)` or thrown errors, recording requests; `StubGoogleAuth` with configurable token, email and errors; `ImmediateSleeper` that records durations):
- `createThenUpdate` (SPEC F-21 AC2): first `exportScope(.all, …)` → requests: about (importFormats with markdown) then POST create; response `{"id": "FILE1"}` → outcome `.exported("FILE1")`, target has `googleFileId "FILE1"`, `lastStatus "ok"`, `lastExportedAt` = now. Second export → a PATCH to `/files/FILE1` (no second about call), same file id.
- `errorsUnauthorizedRefreshesOnce`: 401 then 200 → one forced refresh, success; 401, 401 → `.signInRequired`, status stored.
- `errorsDocMissing`: update returns 404 → `.docMissing`; status `docMissing`; after `clearFileId`, the next export creates a new Doc.
- `errorsRateLimitBackoff`: 429, 503, 200 → success with recorded sleeps [1 s, 4 s]; 429 × 4 → `.failed`, sleeps [1, 4, 16].
- `errorsOffline`: `URLError(.notConnectedToInternet)` → `.queued`, status `queued`.
- `errorsNotConfigured`: `isConfigured == false` → `.notConfigured`, no request sent.
- `htmlFallback`: about without markdown → body part `Content-Type: text/html; charset=UTF-8` containing `<h1>`; target `format == .html`.
- `selectionCreatesNoTarget`: `exportSelection` → POST create, no `exportTarget` rows.
- `folderFromSettings`: `settings.googleExportFolderId = "FOLDER123"` → create metadata has `"parents":["FOLDER123"]`.

## Acceptance criteria
1. First export creates a Doc and stores its ID; re-export updates the same ID. → test `GoogleExportServiceTests/createThenUpdate` (SPEC F-21 AC2)
2. Error cases behave as specified. → tests `GoogleExportServiceTests/errors*` (SPEC F-21 AC3)
3. Requests are byte-exact; HTML fallback and folder parents work; selections save no target. → tests `DriveUploadRequestTests/*`, `htmlFallback`, `folderFromSettings`, `selectionCreatesNoTarget`
4. No `URLSession.shared`, no `Date()`, no `Task.sleep` in the service (code review).

## Out of scope
- GoogleSignIn (T72), UI (T73), keep-in-sync and online retry (T74). Signing (done by the user).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
