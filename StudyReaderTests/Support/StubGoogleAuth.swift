import Foundation
@testable import StudyReader

/// Configurable `GoogleAuthProviding`. Tokens are "token" and, after a forced refresh, "token-refreshed".
actor StubGoogleAuth: GoogleAuthProviding {
    private let configured: Bool
    private let email: String?
    private let error: GoogleAuthError?
    private(set) var tokenRequests: [Bool] = []

    init(configured: Bool = true, email: String? = "student@example.com", error: GoogleAuthError? = nil) {
        self.configured = configured
        self.email = email
        self.error = error
    }

    var isConfigured: Bool {
        configured
    }

    var forcedRefreshCount: Int {
        tokenRequests.filter { $0 }.count
    }

    func currentEmail() async -> String? {
        email
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        tokenRequests.append(forceRefresh)
        if let error { throw error }
        return forceRefresh ? "token-refreshed" : "token"
    }
}
