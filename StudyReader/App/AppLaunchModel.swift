import Observation

/// Opens the long-lived dependencies once at launch and exposes whether the library is ready.
@MainActor @Observable
final class AppLaunchModel {
    enum State {
        case loading
        case ready(AppEnvironment)
        case failed(message: String)
    }

    private(set) var state: State = .loading

    private let makeEnvironment: @Sendable () throws -> AppEnvironment

    /// Default factory: in-memory environment when running as a test host, the user's library otherwise.
    init(makeEnvironment: @escaping @Sendable () throws -> AppEnvironment = AppLaunchModel.defaultFactory) {
        self.makeEnvironment = makeEnvironment
    }

    nonisolated static func defaultFactory() throws -> AppEnvironment {
        if AppEnvironment.usesInMemoryLibrary() {
            return try AppEnvironment.inMemory()
        }
        return try AppEnvironment.live()
    }

    /// Runs the factory once. Success → .ready; error → .failed(message: error.localizedDescription)
    /// and logs via Log.app (no paths or user data in the log). Calling start() again when not .loading does nothing.
    func start() {
        guard case .loading = state else { return }
        do {
            state = .ready(try makeEnvironment())
        } catch {
            Log.app.error("Library failed to open: \(String(describing: type(of: error)), privacy: .public)")
            state = .failed(message: error.localizedDescription)
        }
    }
}
