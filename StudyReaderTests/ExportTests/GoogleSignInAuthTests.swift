import AppKit
import Foundation
import Testing
@testable import StudyReader

@MainActor
private final class StubSigner: GoogleAccountSigningIn {
    var result: Result<String, GoogleAuthError>
    private(set) var signInCount = 0
    private(set) var signOutCount = 0

    init(result: Result<String, GoogleAuthError>) {
        self.result = result
    }

    func signIn(presenting window: NSWindow) async throws -> String {
        signInCount += 1
        return try result.get()
    }

    func signOut() {
        signOutCount += 1
    }
}

@MainActor
struct GoogleSignInAuthTests {
    @Test
    func configurationRule() {
        #expect(!GoogleSignInAuth.isConfigured(clientID: nil))
        #expect(!GoogleSignInAuth.isConfigured(clientID: ""))
        #expect(!GoogleSignInAuth.isConfigured(clientID: "$(GOOGLE_CLIENT_ID)"))
        #expect(GoogleSignInAuth.isConfigured(clientID: "123-abc.apps.googleusercontent.com"))
    }

    @Test
    func driveScopeIsTheOnlyRequestedScope() {
        #expect(GoogleSignInAuth.driveScope == "https://www.googleapis.com/auth/drive.file")
    }

    @Test
    func unconfiguredAuthNeverTouchesTheSDK() async {
        let auth = GoogleSignInAuth(clientID: "")
        #expect(await auth.isConfigured == false)
        #expect(await auth.currentEmail() == nil)
        await auth.restorePreviousSignIn()
        await #expect(throws: GoogleAuthError.notConfigured) {
            try await auth.accessToken(forceRefresh: false)
        }
        let window = NSWindow()
        do {
            _ = try await auth.signIn(presenting: window)
            Issue.record("signIn should throw when Google isn't configured")
        } catch {
            #expect(error as? GoogleAuthError == .notConfigured)
        }
    }

    @Test
    func environmentNeverUsesGoogleSignIn() throws {
        let environment = try AppEnvironment.inMemory()
        defer { try? FileManager.default.removeItem(at: environment.fileStore.rootURL.deletingLastPathComponent()) }
        #expect(environment.googleAuth is UnconfiguredGoogleAuth)
        #expect(environment.googleSignIn == nil)
    }

    @Test
    func infoPlistHasGoogleKeys() {
        let info = Bundle.main.infoDictionary
        #expect(info?["GIDClientID"] != nil)
        #expect(info?["CFBundleURLTypes"] != nil)
    }

    @Test
    func accountModelNotConfigured() async {
        let model = GoogleAccountModel(auth: UnconfiguredGoogleAuth(), signIn: nil)
        await model.refresh()
        #expect(model.isConfigured == false)
        #expect(model.email == nil)
        #expect(model.state == .notConfigured)
    }

    @Test
    func accountModelSignedOut() async {
        let model = GoogleAccountModel(auth: StubGoogleAuth(email: nil), signIn: StubSigner(result: .success("a@example.com")))
        await model.refresh()
        #expect(model.state == .signedOut)
    }

    @Test
    func accountModelRestoredSessionShowsEmail() async {
        let model = GoogleAccountModel(auth: StubGoogleAuth(email: "student@example.com"), signIn: nil)
        await model.refresh()
        #expect(model.state == .signedIn(email: "student@example.com"))
    }

    @Test
    func accountModelSignIn() async {
        let signer = StubSigner(result: .success("new@example.com"))
        let model = GoogleAccountModel(auth: StubGoogleAuth(email: nil), signIn: signer)
        await model.refresh()
        await model.signIn(presenting: NSWindow())
        #expect(signer.signInCount == 1)
        #expect(model.state == .signedIn(email: "new@example.com"))
        #expect(model.errorMessage == nil)
    }

    @Test
    func accountModelSignOut() async {
        let signer = StubSigner(result: .success("a@example.com"))
        let model = GoogleAccountModel(auth: StubGoogleAuth(email: "a@example.com"), signIn: signer)
        await model.refresh()
        model.signOut()
        #expect(signer.signOutCount == 1)
        #expect(model.state == .signedOut)
    }

    @Test
    func accountModelCancelledIsNotAnError() async {
        let model = GoogleAccountModel(
            auth: StubGoogleAuth(email: nil),
            signIn: StubSigner(result: .failure(.cancelled))
        )
        await model.refresh()
        await model.signIn(presenting: NSWindow())
        #expect(model.state == .signedOut)
        #expect(model.errorMessage == nil)
    }

    @Test
    func accountModelSignInFailureShowsMessage() async {
        let model = GoogleAccountModel(
            auth: StubGoogleAuth(email: nil),
            signIn: StubSigner(result: .failure(.signInRequired))
        )
        await model.refresh()
        await model.signIn(presenting: NSWindow())
        #expect(model.state == .signedOut)
        #expect(model.errorMessage != nil)
    }

    @Test
    func accountModelNotConfiguredErrorFromSigner() async {
        let model = GoogleAccountModel(
            auth: StubGoogleAuth(email: nil),
            signIn: StubSigner(result: .failure(.notConfigured))
        )
        await model.refresh()
        await model.signIn(presenting: NSWindow())
        #expect(model.state == .notConfigured)
    }
}
