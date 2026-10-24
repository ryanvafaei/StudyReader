# ADR-0018: Google export seams, statuses and signing

- Status: Accepted (one-off "Export selection" confirmed by the user 2026-10-24, Q3)
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

## Alternatives considered
- Calling GoogleSignIn directly from the service: untestable without a Google account.
- An enum column with a CHECK constraint for statuses: needs migration `v3`.

## Consequences
- Export code is fully testable without network, a Google account or the keychain; only the sign-in visual check needs the user's real credentials.
- Tests and the test host never use GoogleSignIn (`UnconfiguredGoogleAuth` in in-memory environments).
