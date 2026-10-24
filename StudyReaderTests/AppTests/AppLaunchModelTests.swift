import Foundation
import GRDB
import Synchronization
import Testing
@testable import StudyReader

private struct LaunchTestError: LocalizedError {
    var errorDescription: String? { "Disk full" }
}

@Suite("AppLaunchModel") @MainActor
struct AppLaunchModelTests {
    @Test func startBecomesReady() async throws {
        let model = AppLaunchModel { try AppEnvironment.inMemory() }

        await model.start()

        guard case .ready(let environment) = model.state else {
            Issue.record("Expected .ready after start()")
            return
        }
        TestFileStore.remove(environment.fileStore)
    }

    @Test func startReportsFailureOnce() async {
        let calls = Mutex(0)
        let error = AppDatabaseError.migrationFailed(code: 1)
        let model = AppLaunchModel {
            calls.withLock { $0 += 1 }
            throw error
        }

        await model.start()
        await model.start()

        guard case .failed(let message) = model.state else {
            Issue.record("Expected .failed after start()")
            return
        }
        #expect(message == AppLaunchModel.failureMessage(for: error))
        #expect(message.hasPrefix(error.errorDescription ?? ""))
        #expect(message.hasSuffix(error.recoverySuggestion ?? ""))
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func concurrentStartsRunFactoryOnce() async throws {
        let calls = Mutex(0)
        let model = AppLaunchModel {
            calls.withLock { $0 += 1 }
            return try AppEnvironment.inMemory()
        }

        async let first: Void = model.start()
        async let second: Void = model.start()
        _ = await (first, second)

        #expect(calls.withLock { $0 } == 1)
        guard case .ready(let environment) = model.state else {
            Issue.record("Expected .ready after concurrent start()")
            return
        }
        TestFileStore.remove(environment.fileStore)
    }

    @Test func factoryRunsOffMainThread() async throws {
        let wasMainThread = Mutex<Bool?>(nil)
        let model = AppLaunchModel {
            wasMainThread.withLock { $0 = Thread.isMainThread }
            return try AppEnvironment.inMemory()
        }

        await model.start()

        #expect(wasMainThread.withLock { $0 } == false)
        guard case .ready(let environment) = model.state else {
            Issue.record("Expected .ready after start()")
            return
        }
        TestFileStore.remove(environment.fileStore)
    }

    @Test func unknownErrorsShowGenericMessage() async {
        let rawError = DatabaseError(resultCode: .SQLITE_ERROR, message: "near \"CREATE\": syntax error", sql: "CREATE TABLE x (")
        let rawModel = AppLaunchModel { throw rawError }
        await rawModel.start()

        let localizedModel = AppLaunchModel { throw LaunchTestError() }
        await localizedModel.start()

        guard case .failed(let rawMessage) = rawModel.state,
              case .failed(let localizedMessage) = localizedModel.state else {
            Issue.record("Expected .failed for both models")
            return
        }
        #expect(rawMessage == AppLaunchModel.genericFailureMessage)
        #expect(!rawMessage.contains("CREATE"))
        #expect(localizedMessage == AppLaunchModel.genericFailureMessage)
    }
}
