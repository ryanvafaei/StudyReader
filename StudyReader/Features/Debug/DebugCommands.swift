#if DEBUG
import SwiftUI

/// DEBUG-only Debug menu. Nothing seeds or removes on launch; only these menu items change the library.
@MainActor
struct DebugCommands: Commands {
    let launchModel: AppLaunchModel

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Seed Sample Library") {
                perform("seed") { environment in
                    try await SampleLibrary(environment: environment).seed()
                }
            }
            Button("Remove Sample Library") {
                perform("remove") { environment in
                    try await SampleLibrary(environment: environment).removeSamples()
                }
            }
        }
    }

    /// Runs one sample operation against the open library. Failures are logged; the menu has no alert.
    private func perform(
        _ name: String,
        _ operation: @escaping @Sendable (AppEnvironment) async throws -> Int
    ) {
        guard let environment = launchModel.session?.environment else {
            Log.files.error("Debug \(name, privacy: .public) skipped: the library isn't open")
            return
        }
        Task {
            do {
                let count = try await operation(environment)
                Log.files.info("Debug \(name, privacy: .public) finished with \(count, privacy: .public) documents")
            } catch {
                Log.files.error("Debug \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
#endif
