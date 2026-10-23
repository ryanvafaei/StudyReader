import Foundation
import Synchronization
import Testing
@testable import StudyReader

private struct LaunchTestError: LocalizedError {
    var errorDescription: String? { "Disk full" }
}

@Suite("AppLaunchModel")
@MainActor
struct AppLaunchModelTests {
    @Test func startBecomesReady() throws {
        let model = AppLaunchModel { try AppEnvironment.inMemory() }

        model.start()

        guard case .ready = model.state else {
            Issue.record("Expected .ready after start()")
            return
        }
    }

    @Test func startReportsFailureOnce() {
        let calls = Mutex(0)
        let model = AppLaunchModel {
            calls.withLock { $0 += 1 }
            throw LaunchTestError()
        }

        model.start()
        model.start()

        guard case .failed(let message) = model.state else {
            Issue.record("Expected .failed after start()")
            return
        }
        #expect(message == "Disk full")
        #expect(calls.withLock { $0 } == 1)
    }
}
