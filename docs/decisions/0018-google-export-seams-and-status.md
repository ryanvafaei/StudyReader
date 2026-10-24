# ADR-0018: Google export seams, statuses and signing

- Status: Accepted (one-off "Export selection" pending user confirmation, Phase 1 open question Q3)
- Date: 2026-10-24 (Phase 1 planning)

## Context
ADR-0007 and ARCHITECTURE §9 define the Drive calls. Tests must cover create, update and every error without network or a Google account. `exportTarget.lastStatus` is free text in the schema. GoogleSignIn needs team signing and a keychain access group (ADR-0011), which also changes how every build is signed.

## Decision
- `HTTPClient` protocol (`func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)`); the app uses `URLSessionHTTPClient` over an ephemeral `URLSession`. Never `URLSession.shared`.
- `GoogleAuthProviding` protocol (`isConfigured`, `currentEmail()`, `accessToken(forceRefresh:)`). `GoogleSignInAuth` wraps `GIDSignIn` on the main actor. `GoogleExportService` only sees the protocol, so tests use stubs.
- `ExportStatus` raw values stored in `lastStatus`: `never`, `ok`, `queued`, `failed`, `docMissing`, `signInRequired`. No other values are written.
- Google isn't configured when `GIDClientID` in Info.plist is empty or still contains `$(`. Then export UI shows "Google export not configured" and makes no request.
- Backoff waits go through `Sleeper` (ADR-0015): 1 s, 4 s, 16 s.
- Signing (ADR-0011): the sign-in task sets `DEVELOPMENT_TEAM: 597KGSTZWJ`, `CODE_SIGN_IDENTITY: "Apple Development"` and the entitlement `keychain-access-groups = [$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)]` in `project.yml`. From then on every build, including tests, is team-signed.
- "Export selection" from the highlights browser creates a new Doc each time and saves no export target (proposed).
- Never log tokens, auth codes, emails or document contents; log status codes and target IDs only.

## Alternatives considered
- Calling GoogleSignIn directly from the service: untestable without a Google account.
- An enum column with a CHECK constraint for statuses: needs migration `v3`.

## Consequences
- After the sign-in task, command-line builds need the team's development certificate and a provisioning profile on this Mac. If `xcodebuild` can't create the profile, the user opens the project in Xcode once (Signing & Capabilities) so Xcode creates it.
