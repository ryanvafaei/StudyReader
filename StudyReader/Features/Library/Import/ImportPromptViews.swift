import SwiftUI

extension View {
    /// Attaches the import questions (password sheet, large-file alert) and the summary alert to a window.
    func importPrompts(_ coordinator: ImportCoordinator) -> some View {
        modifier(ImportPromptsModifier(coordinator: coordinator))
    }
}

/// Sheet, alerts and bindings for `ImportCoordinator`. Dismissing a prompt answers it with the safe default
/// (skip or decline); answering it in code first makes the later dismissal a no-op.
private struct ImportPromptsModifier: ViewModifier {
    let coordinator: ImportCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(item: passwordBinding) { request in
                PasswordPromptView(request: request) { password in
                    coordinator.answerPassword(password)
                }
            }
            .alert(
                "Large File",
                isPresented: largeFileBinding,
                presenting: coordinator.largeFileRequest
            ) { _ in
                Button("Import") {
                    coordinator.answerLargeFile(true)
                }
                Button("Skip", role: .cancel) {
                    coordinator.answerLargeFile(false)
                }
            } message: { request in
                Text("\(request.fileName) is larger than 500 MB. Import it anyway?")
            }
            .alert("Import finished", isPresented: summaryBinding) {
                Button("OK") {
                    coordinator.lastSummary = nil
                }
            } message: {
                Text(coordinator.lastSummary ?? "")
            }
    }

    private var passwordBinding: Binding<ImportCoordinator.PasswordRequest?> {
        Binding(
            get: { coordinator.passwordRequest },
            set: { request in
                if request == nil {
                    coordinator.answerPassword(nil)
                }
            }
        )
    }

    private var largeFileBinding: Binding<Bool> {
        Binding(
            get: { coordinator.largeFileRequest != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.answerLargeFile(false)
                }
            }
        )
    }

    private var summaryBinding: Binding<Bool> {
        Binding(
            get: { coordinator.lastSummary != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.lastSummary = nil
                }
            }
        )
    }
}

/// Asks for the password of one locked PDF. Skip answers nil; Unlock answers the typed password.
struct PasswordPromptView: View {
    let request: ImportCoordinator.PasswordRequest
    let onAnswer: (String?) -> Void
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Password Required")
                .font(.headline)
            Text("Enter the password for \(request.fileName).")
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Password")
            HStack {
                Spacer()
                Button("Skip", role: .cancel) {
                    onAnswer(nil)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Skip this file")
                Button("Unlock") {
                    onAnswer(password)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
                .accessibilityLabel("Unlock with this password")
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// Highlight shown over the main window while a drag hovers over it.
struct ImportDropOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.12)
            Label("Drop to import", systemImage: "square.and.arrow.down")
                .font(.title2.weight(.semibold))
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .overlay {
            Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
        }
        .allowsHitTesting(false)
    }
}
