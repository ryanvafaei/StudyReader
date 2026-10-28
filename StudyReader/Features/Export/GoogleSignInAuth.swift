import AppKit
import Foundation
import GoogleSignIn
import os

/// What `GoogleAccountModel` needs to sign in and out. `GoogleSignInAuth` is the real implementation; tests use stubs.
@MainActor
protocol GoogleAccountSigningIn {
    /// Shows Google's sign-in in `window`. Returns the account email (never log it). Throws `GoogleAuthError`.
    func signIn(presenting window: NSWindow) async throws -> String
    func signOut()
}

/// GoogleSignIn wrapper (ADR-0018). No stored mutable state, so it is Sendable; every `GIDSignIn` call runs on the
/// main actor. When Google isn't configured (no client ID in this build) it never touches the SDK.
/// Never logs tokens, auth codes or emails.
final class GoogleSignInAuth: GoogleAuthProviding, Sendable {
    static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private static let log = Log.logger("google")

    private let clientID: String?

    /// false for nil, "" (`GOOGLE_CLIENT_ID` empty) or a value containing "$(" (build setting not expanded).
    static func isConfigured(clientID: String?) -> Bool {
        guard let clientID, !clientID.isEmpty else { return false }
        return !clientID.contains("$(")
    }

    /// `GIDClientID` from the app's Info.plist (set from `GOOGLE_CLIENT_ID`).
    static var bundleClientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    init(clientID: String?) {
        self.clientID = clientID
    }

    private var configured: Bool {
        Self.isConfigured(clientID: clientID)
    }

    // MARK: GoogleAuthProviding

    var isConfigured: Bool {
        get async { configured }
    }

    func currentEmail() async -> String? {
        guard configured else { return nil }
        return await Self.signedInEmail()
    }

    /// `forceRefresh` can't force a refresh through GoogleSignIn's public API (only `refreshTokensIfNeeded`), so when
    /// the token comes back unchanged after a 401 the token was rejected and only a new sign-in helps.
    func accessToken(forceRefresh: Bool) async throws -> String {
        guard configured else { throw GoogleAuthError.notConfigured }
        return try await Self.token(forceRefresh: forceRefresh)
    }

    // MARK: Sign-in, restore, sign-out

    /// Silent, at launch. A no-op when not configured or when nobody signed in before.
    func restorePreviousSignIn() async {
        guard configured else { return }
        await Self.restore()
    }

    @MainActor
    func signIn(presenting window: NSWindow) async throws -> String {
        guard configured else { throw GoogleAuthError.notConfigured }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: [Self.driveScope]
            )
            guard result.user.grantedScopes?.contains(Self.driveScope) == true else {
                // The user declined file access on Google's consent page.
                GIDSignIn.sharedInstance.signOut()
                throw GoogleAuthError.signInRequired
            }
            return result.user.profile?.email ?? ""
        } catch let error as GoogleAuthError {
            throw error
        } catch let error as GIDSignInError where error.code == .canceled {
            throw GoogleAuthError.cancelled
        } catch {
            Self.log.error("Google sign-in failed: \(Self.describe(error), privacy: .public)")
            throw Self.mapped(error)
        }
    }

    @MainActor
    func signOut() {
        guard configured else { return }
        GIDSignIn.sharedInstance.signOut()
    }

    /// Passes the sign-in redirect URL to GoogleSignIn. false when it isn't a Google URL or Google isn't configured.
    @MainActor
    static func handle(_ url: URL) -> Bool {
        guard isConfigured(clientID: bundleClientID) else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: Main-actor SDK access

    @MainActor
    private static func signedInEmail() -> String? {
        GIDSignIn.sharedInstance.currentUser?.profile?.email
    }

    @MainActor
    private static func restore() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do {
            _ = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        } catch {
            log.error("Restoring the Google sign-in failed: \(describe(error), privacy: .public)")
        }
    }

    @MainActor
    private static func token(forceRefresh: Bool) async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser,
              user.grantedScopes?.contains(driveScope) == true else {
            throw GoogleAuthError.signInRequired
        }
        let previous = user.accessToken.tokenString
        let refreshed: String
        do {
            refreshed = try await user.refreshTokensIfNeeded().accessToken.tokenString
        } catch {
            log.error("Refreshing the Google token failed: \(describe(error), privacy: .public)")
            throw mapped(error)
        }
        if forceRefresh && refreshed == previous {
            throw GoogleAuthError.signInRequired
        }
        return refreshed
    }

    // MARK: Errors

    /// Network failures stay `URLError` (the export service queues them); anything else needs a new sign-in.
    private static func mapped(_ error: any Error) -> any Error {
        if let urlError = error as? URLError { return urlError }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code))
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: underlying.code))
        }
        return GoogleAuthError.signInRequired
    }

    /// Domain and code only: error descriptions can contain account details.
    private static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}

// A separate extension so the protocol's main-actor isolation isn't inferred for the whole class.
extension GoogleSignInAuth: GoogleAccountSigningIn {}
