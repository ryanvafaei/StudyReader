import Foundation
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
    private var hasStarted = false

    private let makeEnvironment: @Sendable () throws -> AppEnvironment

    /// Generic text for errors that aren't AppDatabaseError (never shows their description).
    /// `nonisolated` so the nonisolated failureMessage(for:) can read it.
    nonisolated static let genericFailureMessage = String(localized: "StudyReader couldn't open its library. Quit and reopen StudyReader.")

    /// Default factory: defaultFactory() (in-memory library when any test-host signal is set, the user's library otherwise).
    init(makeEnvironment: @escaping @Sendable () throws -> AppEnvironment = AppLaunchModel.defaultFactory) {
        self.makeEnvironment = makeEnvironment
    }

    nonisolated static func defaultFactory() throws -> AppEnvironment {
        try chooseEnvironment(
            for: AppEnvironment.launchTestHostSignals,
            live: { try AppEnvironment.live() },
            inMemory: { try AppEnvironment.inMemory() }
        )
    }

    /// The only place that chooses the library (ADR-0011). Any test-host signal → `inMemory`.
    /// `live` runs only when every signal is false.
    nonisolated static func chooseEnvironment(
        for signals: AppEnvironment.TestHostSignals,
        live: () throws -> AppEnvironment,
        inMemory: () throws -> AppEnvironment
    ) rethrows -> AppEnvironment {
        if signals.usesInMemoryLibrary {
            Log.app.info("Using the in-memory library (xctestEnvironment: \(signals.xctestEnvironment, privacy: .public), inMemoryRequested: \(signals.inMemoryRequested, privacy: .public), xctestLibraryLoaded: \(signals.xctestLibraryLoaded, privacy: .public))")
            return try inMemory()
        }
        return try live()
    }

    /// AppDatabaseError → errorDescription, plus "\n\n" + recoverySuggestion when present.
    /// Any other error → genericFailureMessage.
    nonisolated static func failureMessage(for error: any Error) -> String {
        guard let databaseError = error as? AppDatabaseError else {
            return genericFailureMessage
        }
        let description = databaseError.errorDescription ?? genericFailureMessage
        guard let suggestion = databaseError.recoverySuggestion else {
            return description
        }
        return description + "\n\n" + suggestion
    }

    /// Runs the factory once, off the main actor. Success → .ready; failure → .failed(message:).
    /// Calls after the first return immediately, even while the first is still running.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let factory = makeEnvironment
        let result = await Task.detached(priority: .userInitiated) {
            Result { try factory() }
        }.value
        switch result {
        case .success(let environment):
            state = .ready(environment)
        case .failure(let error):
            Log.app.error("Library failed to open: \(String(describing: type(of: error)), privacy: .public)")
            state = .failed(message: Self.failureMessage(for: error))
        }
    }
}
