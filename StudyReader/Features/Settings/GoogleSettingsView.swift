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
    /// true after the first `refresh()` finished, so the view doesn't flash "not configured" while loading.
    private(set) var hasLoaded = false
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
        hasLoaded = true
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

/// The Google tab of the Settings window: account, export folder and export targets (T73).
struct GoogleSettingsView: View {
    @State private var model: GoogleAccountModel
    @State private var targets: ExportTargetsModel
    @State private var pendingRemove: ExportTarget?

    init(session: AppSession) {
        let environment = session.environment
        _model = State(initialValue: GoogleAccountModel(auth: environment.googleAuth, signIn: environment.googleSignIn))
        _targets = State(initialValue: ExportTargetsModel(session: session))
    }

    var body: some View {
        Form {
            Section("Account") {
                if !model.hasLoaded {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading Google account")
                } else {
                    accountContent
                }
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel(message)
                }
            }
            if model.hasLoaded, model.state != .notConfigured {
                folderSection
                targetsSection
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
        .task { await targets.observe() }
        .confirmationDialog(
            "Remove this export target? The Google Doc isn't deleted.",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let target = pendingRemove {
                    Task { await targets.remove(target.id) }
                }
                pendingRemove = nil
            }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    @ViewBuilder
    private var accountContent: some View {
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
    }

    private var signInButton: some View {
        Button("Sign in with Google") {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            Task { await model.signIn(presenting: window) }
        }
        .accessibilityLabel("Sign in with Google")
    }

    // MARK: - Export folder and targets

    private var folderSection: some View {
        Section("Export folder") {
            HStack {
                TextField("Drive folder link or ID", text: $targets.folderLink)
                    .labelsHidden()
                    .onSubmit { targets.saveFolder() }
                    .accessibilityLabel("Export folder link")
                Button("Save") { targets.saveFolder() }
                    .accessibilityLabel("Save export folder")
            }
            if let message = targets.folderError {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityLabel(message)
            }
            Text("Leave empty to export to the top level of your Drive.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var targetsSection: some View {
        Section("Export targets") {
            if targets.targets.isEmpty {
                Text("No export targets yet. Use File > Export Highlights… to create one.")
                    .foregroundStyle(.secondary)
            } else {
                Table(targets.targets) {
                    TableColumn("Title") { target in
                        Text(target.title).lineLimit(1)
                    }
                    TableColumn("Status") { target in
                        Text(ExportTargetsModel.statusText(target))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Actions") { target in
                        targetActions(target)
                    }
                    .width(min: 150, ideal: 170)
                }
                .frame(minHeight: 150)
                .accessibilityLabel("Export targets")
            }
        }
    }

    private func targetActions(_ target: ExportTarget) -> some View {
        HStack(spacing: 6) {
            Toggle("Keep in sync", isOn: Binding(
                get: { target.keepInSync },
                set: { on in Task { await targets.setKeepInSync(target.id, on) } }
            ))
            .labelsHidden()
            .help("Keep in sync")
            .accessibilityLabel(String(localized: "Keep \(target.title) in sync"))

            Menu {
                if let fileId = target.googleFileId {
                    Button("Open in Google Docs") {
                        NSWorkspace.shared.open(ExportTargetsModel.docURL(fileId: fileId))
                    }
                }
                let inFlight = targets.exportingIds.contains(target.id)
                Button("Export Now") { Task { await targets.exportNow(target.id) } }
                    .disabled(inFlight)
                if target.lastStatus == ExportStatus.docMissing.rawValue {
                    Button("Create New Doc") { Task { await targets.createNewDoc(target.id) } }
                        .disabled(inFlight)
                }
                Divider()
                Button("Remove…", role: .destructive) { pendingRemove = target }
            } label: {
                Text("Actions")
            }
            .fixedSize()
            .accessibilityLabel(String(localized: "Actions for \(target.title)"))
        }
    }
}
