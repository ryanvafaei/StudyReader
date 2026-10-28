import AppKit
import Observation
import SwiftUI

/// Settings > Google account state: not configured, signed out, signing in, signed in, or an error message.
@MainActor @Observable
final class GoogleAccountModel {
    enum State: Equatable {
        case notConfigured
        case signedOut
        case signingIn
        case signedIn(email: String)
    }

    private let auth: any GoogleAuthProviding
    private let signInProvider: (any GoogleAccountSigningIn)?

    private(set) var isConfigured = false
    private(set) var isSigningIn = false
    /// Never logged.
    private(set) var email: String?
    private(set) var errorMessage: String?

    /// `signIn` is nil in tests and when Google isn't configured.
    init(auth: any GoogleAuthProviding, signIn: (any GoogleAccountSigningIn)?) {
        self.auth = auth
        self.signInProvider = signIn
    }

    var state: State {
        if !isConfigured { return .notConfigured }
        if isSigningIn { return .signingIn }
        if let email { return .signedIn(email: email) }
        return .signedOut
    }

    /// Reads the configuration and the signed-in account from the auth provider.
    func refresh() async {
        let configured = await auth.isConfigured
        let currentEmail = configured ? await auth.currentEmail() : nil
        isConfigured = configured
        if !isSigningIn {
            email = currentEmail
        }
    }

    func signIn(presenting window: NSWindow) async {
        guard let signInProvider, !isSigningIn else { return }
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let signedInEmail = try await signInProvider.signIn(presenting: window)
            email = signedInEmail.isEmpty ? nil : signedInEmail
            isConfigured = true
        } catch GoogleAuthError.cancelled {
            // The user closed Google's window: not an error.
        } catch GoogleAuthError.notConfigured {
            isConfigured = false
        } catch GoogleAuthError.signInRequired {
            errorMessage = String(localized: "Google didn't give StudyReader access to the files it creates. Try again and allow access.")
        } catch {
            errorMessage = String(localized: "Couldn't sign in to Google. Check your connection and try again.")
        }
    }

    func signOut() {
        signInProvider?.signOut()
        email = nil
        errorMessage = nil
    }
}

/// The Google tab of the Settings window. Folder and export targets arrive with T73.
struct GoogleSettingsView: View {
    @State private var model: GoogleAccountModel

    init(environment: AppEnvironment) {
        _model = State(initialValue: GoogleAccountModel(auth: environment.googleAuth, signIn: environment.googleSignIn))
    }

    var body: some View {
        Form {
            Section("Account") {
                switch model.state {
                case .notConfigured:
                    Text("Google export not configured")
                    Text("Set GOOGLE_CLIENT_ID as described in DEPENDENCIES.md §4.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .signedOut:
                    signInButton
                    Text("StudyReader only asks for access to the files it creates in your Google Drive.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .signingIn:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Signing in…")
                    }
                case .signedIn(let email):
                    LabeledContent("Signed in as") {
                        Text(email).textSelection(.enabled)
                    }
                    Button("Sign Out") { model.signOut() }
                        .accessibilityLabel("Sign out of Google")
                }
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel(message)
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    private var signInButton: some View {
        Button("Sign in with Google") {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            Task { await model.signIn(presenting: window) }
        }
        .accessibilityLabel("Sign in with Google")
    }
}
