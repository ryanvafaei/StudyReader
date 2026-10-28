# ADR-0018: Google export seams, statuses and signing

- Status: Accepted (one-off "Export selection" confirmed by the user 2026-10-24, Q3; amended 2026-10-28: T80, bug hunt H2 app folder, bug hunt M1/M2 error mapping)
- Date: 2026-10-24 (Phase 1 planning)

## Context
ADR-0007 and ARCHITECTURE §9 define the Drive calls. Tests must cover create, update and every error without network or a Google account. `exportTarget.lastStatus` is free text in the schema. GoogleSignIn needs team signing and a keychain access group (ADR-0011), which also changes how every build is signed.

## Decision
- `HTTPClient` protocol (`func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)`); the app uses `URLSessionHTTPClient` over an ephemeral `URLSession`. Never `URLSession.shared`.
- `GoogleAuthProviding` protocol (`isConfigured`, `currentEmail()`, `accessToken(forceRefresh:)`). `GoogleSignInAuth` wraps `GIDSignIn` on the main actor. `GoogleExportService` only sees the protocol, so tests use stubs.
- `ExportStatus` raw values stored in `lastStatus`: `never`, `ok`, `queued`, `failed`, `docMissing`, `signInRequired`. No other values are written.
- Credentials come from build settings: `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` (defaults in `Config/Base.xcconfig`, overridden by the user's `Secrets/Google.xcconfig`, which agents never read). Info.plist maps them to `GIDClientID` and the `CFBundleURLSchemes` entry. At runtime Google is "not configured" when `GIDClientID` is empty (the `Base.xcconfig` default) or still contains `$(`. Then the export UI and Settings > Google show "Google export not configured" and no request is made.
- Backoff waits go through `Sleeper` (ADR-0015): 1 s, 4 s, 16 s.
- Signing (ADR-0011, amended): the user already set `DEVELOPMENT_TEAM: "597KGSTZWJ"` and `keychain-access-groups = ["$(AppIdentifierPrefix)com.ryanvafaei.StudyReader"]` in `project.yml`; the scripts pass `-allowProvisioningUpdates`. No export task touches signing. GoogleSignIn keeps its tokens in that keychain group, so a sign-in survives an app restart; the sign-in task (T72) verifies this.
- "Export selection" from the highlights browser creates a new Doc each time and saves no export target.
- Never log tokens, auth codes, emails or document contents; log status codes and target IDs only.
- Amendment 2026-10-28 (T80): `ExportOutcome.cancelled` for a cancelled request or backoff wait. Like `notConfigured` it writes nothing to the target (no status, no error); the scheduler doesn't retry it. The stored status values above are unchanged.
- Amendment 2026-10-28 (bug hunt H2, user decision; T92a/T92b): **the export folder is the app's own "StudyReader" folder.** `drive.file` only covers files the app created or the user picked through the Google Picker, so a folder made in the Drive web UI and pasted as a link can't be a parent (Drive answers 404/403 on `files.create`). So: the app creates a folder named `StudyReader` in My Drive on the first create (or reuses the oldest non-trashed app-visible one, found with `files.list`), stores its ID per Google account in `SettingsStore` (key = SHA-256 of the lowercased email, never the email itself), verifies it with `files.get` before each create, and recreates it when it is gone or trashed. A moved folder keeps working (IDs survive moves). Folder resolution runs behind one actor gate, so concurrent first exports create one folder. The pasted-link field is removed; an old pasted ID is ignored. Possible later work, not built (BACKLOG): the Google Picker for desktop apps (browser flow with the Picker API and `trigger_onepick`) to let the user pick any folder.
- Amendment 2026-10-28 (bug hunt M1/M2, T94): Drive 403s are mapped by `error.errors[].reason` (ARCHITECTURE §9.2). Only 404 or a trashed Doc means `docMissing`; quota, rate-limit and permission 403s are `failed` and keep `googleFileId`. Export Selection never returns `.queued` (it has no target to retry). No new stored status values.

## Alternatives considered
- Calling GoogleSignIn directly from the service: untestable without a Google account.
- An enum column with a CHECK constraint for statuses: needs migration `v3`.
- (H2) Keep the pasted-link field and explain the 404: the field could never work under `drive.file`. A broader `drive` scope: needs Google's restricted-scope verification. The Google Picker now: a browser flow and a Picker API key, more than Phase 1 needs (BACKLOG).

## Consequences
- Export code is fully testable without network, a Google account or the keychain; only the sign-in visual check needs the user's real credentials.
- Tests and the test host never use GoogleSignIn (`UnconfiguredGoogleAuth` in in-memory environments).
