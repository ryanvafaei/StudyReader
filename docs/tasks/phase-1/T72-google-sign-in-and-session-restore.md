# T72: Google sign-in and session restore

- **Phase:** 1 (E1.8: F-21 sign-in, F-22 Google tab, account part)
- **Agent:** integrations
- **Depends on:** T45, T71
- **ADRs:** docs/decisions/0018-google-export-seams-and-status.md (read in full), docs/decisions/0011-build-signing-and-test-hosting.md (signing amendment: already done by the user), docs/decisions/0007-google-export-drive-conversion.md; DEPENDENCIES.md §4
- **Visual check needed:** yes (manual Google sign-in with the user's real credentials)

## Goal
Add GoogleSignIn sign-in and sign-out with the `drive.file` scope, the sign-in URL callback, silent restore at launch, and the account part of Settings > Google. Verify that a sign-in survives an app restart (GoogleSignIn keeps the token in the Keychain access group the user already configured).

Signing is already done by the user (ADR-0011 amendment): `DEVELOPMENT_TEAM` is `597KGSTZWJ`, `keychain-access-groups` is in the entitlements, and the scripts pass `-allowProvisioningUpdates`. **This task doesn't change `project.yml`, the entitlements, `Config/` or any signing setting.** Google credentials are also set up by the user: `Secrets/Google.xcconfig` exists and `Config/Base.xcconfig` includes it. **Never read or print anything in `Secrets/`.**

## Files to touch
- `StudyReader/Features/Export/GoogleSignInAuth.swift` (new)
- `StudyReader/Features/Settings/GoogleSettingsView.swift` (new: account section + `GoogleAccountModel`)
- `StudyReader/Features/Settings/SettingsView.swift` (modify: add the Google tab)
- `StudyReader/App/AppEnvironment.swift`, `StudyReader/App/StudyReaderApp.swift`, `StudyReader/App/AppDelegate.swift` (modify)
- `StudyReaderTests/ExportTests/GoogleSignInAuthTests.swift` (new)

## Configuration (ADR-0018)
- Credentials reach the app only through the build settings `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID`, which Info.plist already maps to `GIDClientID` and the `CFBundleURLSchemes` entry (from `project.yml`; don't change them).
- At runtime, read `GIDClientID` from `Bundle.main`. If it's empty (the `Config/Base.xcconfig` default when `GOOGLE_CLIENT_ID` is empty) or contains `$(`, Google is not configured: the app shows "Google export not configured" and never calls GoogleSignIn.

## Interfaces to produce
```swift
/// GoogleSignIn wrapper (ADR-0018). No stored mutable state, so it's Sendable and can be built in live();
/// every GIDSignIn call hops to the main actor (await MainActor.run { … }).
final class GoogleSignInAuth: GoogleAuthProviding, Sendable {
    static let driveScope = "https://www.googleapis.com/auth/drive.file"
    /// false for nil, "" (GOOGLE_CLIENT_ID empty) or a value containing "$(".
    static func isConfigured(clientID: String?) -> Bool
    init(clientID: String?)                                  // live(): Bundle.main "GIDClientID"
    // GoogleAuthProviding (isConfigured, currentEmail(), accessToken(forceRefresh:)):
    // accessToken uses GIDSignIn.sharedInstance.currentUser; nil → .signInRequired; refreshTokensIfNeeded
    // (forceRefresh → refresh even if still valid); drive scope missing from grantedScopes → .signInRequired.
    // Not configured → .notConfigured.
    func restorePreviousSignIn() async                       // at launch, silent; no-op when not configured
    /// Presents Google's sign-in in `window`, requesting driveScope. Returns the email.
    @MainActor func signIn(presenting window: NSWindow) async throws -> String
    @MainActor func signOut()
    static func handle(_ url: URL) -> Bool                   // GIDSignIn.sharedInstance.handle(url), on the main actor
}

/// Settings > Google account state.
@MainActor @Observable
final class GoogleAccountModel {
    init(auth: any GoogleAuthProviding, signIn: GoogleSignInAuth?)   // signIn nil in tests / not configured
    private(set) var isConfigured = false
    private(set) var email: String?
    private(set) var errorMessage: String?
    func refresh() async
    func signIn(presenting window: NSWindow) async
    func signOut()
}
```
- `AppEnvironment`: new `let googleSignIn: GoogleSignInAuth?` (initializer parameter, default nil). `live()` creates one `GoogleSignInAuth(clientID:)`, passes it as both `googleSignIn` and `googleAuth`, and `startBackgroundWork()` calls `googleSignIn?.restorePreviousSignIn()`. `inMemory()` and the default initializer keep `UnconfiguredGoogleAuth` (T71), so tests and the test host never touch GoogleSignIn or the keychain. The export service only sees `any GoogleAuthProviding`.
- URL callback: `StudyReaderApp` adds `.onOpenURL { _ = GoogleSignInAuth.handle($0) }` on the main window; `AppDelegate.application(_:open:)` passes non-file URLs to `GoogleSignInAuth.handle` instead of the importer.
- `GoogleSettingsView` (Settings > Google): not configured → "Google export not configured" plus the hint "Set GOOGLE_CLIENT_ID as described in DEPENDENCIES.md §4."; signed out → "Sign in with Google"; signed in → the email and "Sign Out". The export folder and targets are added by T73.
- Logging: never the email, tokens or auth codes.

## Tests (`GoogleSignInAuthTests`)
- `configurationRule`: `isConfigured(clientID:)` false for nil, `""`, `"$(GOOGLE_CLIENT_ID)"`; true for `"123-abc.apps.googleusercontent.com"`.
- `testEnvironmentNeverUsesGoogleSignIn`: `AppEnvironment.inMemory().googleAuth is UnconfiguredGoogleAuth` and `googleSignIn == nil` (remove the folder).
- `infoPlistHasGoogleKeys`: the host app's `Bundle.main.infoDictionary` contains the keys `GIDClientID` and `CFBundleURLTypes` (don't assert or log their values).
- `accountModelNotConfigured`: `GoogleAccountModel(auth: UnconfiguredGoogleAuth(), signIn: nil)`; after `refresh()`, `isConfigured == false`, `email == nil`.

## Acceptance criteria
1. The configuration rule, test isolation and Info.plist wiring hold. → tests `GoogleSignInAuthTests/*`
2. The diff doesn't touch `project.yml`, `StudyReader/Resources/StudyReader.entitlements`, `Config/`, `scripts/` or `Secrets/`. → code review
3. Visual check (user): Settings > Google shows "Sign in with Google"; signing in opens Google's page, asks only for access to files the app creates, and returns to the app showing the email.
4. Visual check (user), session restore: quit StudyReader and relaunch → Settings > Google still shows the email without signing in again (the token was kept in the Keychain). "Sign Out", then relaunch → signed out.
5. Visual check (user, optional): with `GOOGLE_CLIENT_ID` empty, the tab shows "Google export not configured".

## Out of scope
- Signing, entitlements and credentials (done by the user). Export UI, folder setting and targets list (T73), sync (T74).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-28, implementer integrations Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). GoogleSignIn wrapped behind protocols, drive.file only, no tokens/emails logged, forbidden files untouched, unconfigured builds never call the SDK; 13 tests ran on CI. Sign-in, restore across relaunch and the not-configured state are Mac checks (VISUAL_CHECKS); confirm the SDK picks up GIDClientID from Info.plist (else set GIDConfiguration explicitly). BACKLOG B32.

> **Note (T74a, 2026-10-28):** the `.onOpenURL` described above was removed again: a scene-level `.onOpenURL` stops SwiftUI from calling `AppDelegate.application(_:open:)`, which broke Finder Open With. `AppDelegate.application(_:open:)` is the single entry point (file URLs → ExternalURLRouter, others → GoogleSignInAuth.handle via `ExternalURLRouter.split`).
