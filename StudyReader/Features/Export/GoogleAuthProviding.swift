import Foundation

enum GoogleAuthError: Error, Equatable {
    /// No Google client ID in this build (ADR-0018).
    case notConfigured
    /// No signed-in user, or the refresh token no longer works.
    case signInRequired
    /// The user closed the sign-in window.
    case cancelled
}

/// Google sign-in as `GoogleExportService` sees it (ADR-0018). The real implementation wraps `GIDSignIn` (T72);
/// tests use stubs. Implementations never log tokens or emails.
protocol GoogleAuthProviding: Sendable {
    /// false when `GIDClientID` is empty or still contains `$(`.
    var isConfigured: Bool { get async }
    /// The signed-in account's email, or nil when nobody is signed in. Never log it.
    func currentEmail() async -> String?
    /// A fresh access token for the `drive.file` scope; `forceRefresh` after a 401. Throws `GoogleAuthError`.
    func accessToken(forceRefresh: Bool) async throws -> String
}

/// Used until Google sign-in is available, in tests and in the in-memory library: not configured, every call throws.
struct UnconfiguredGoogleAuth: GoogleAuthProviding {
    init() {}

    var isConfigured: Bool {
        get async { false }
    }

    func currentEmail() async -> String? {
        nil
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        throw GoogleAuthError.notConfigured
    }
}
