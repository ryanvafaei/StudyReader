import Foundation
import Observation

/// Shared state for every window of this app run. Created on the main actor when the library is ready.
@MainActor @Observable
final class AppSession {
    let environment: AppEnvironment
    let settings: AppSettings

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = AppSettings(store: environment.settingsStore)
    }
}
