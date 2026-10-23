import Foundation
import Testing
@testable import StudyReader

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    @Test func makeCreatesOnDiskDatabase() async throws {
        let fileStore = TestFileStore.make()
        defer { removeParent(of: fileStore) }

        let environment = try AppEnvironment.make(fileStore: fileStore)
        let categories = try await environment.categoryRepository.fetchAll()

        #expect(FileManager.default.fileExists(atPath: fileStore.databaseURL.path(percentEncoded: false)))
        #expect(categories.count == 5)
    }

    @Test func inMemoryEnvironmentIsEmpty() async throws {
        let environment = try AppEnvironment.inMemory()
        let documents = try await environment.documentRepository.fetchAll()
        let rootPath = environment.fileStore.rootURL.path(percentEncoded: false)
        let temporaryPath = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        defer { removeParent(of: environment.fileStore) }

        #expect(documents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: rootPath))
        #expect(rootPath.hasPrefix(temporaryPath))
    }

    @Test func detectsTestHost() {
        #expect(AppEnvironment.isRunningUnitTests(environment: ["XCTestConfigurationFilePath": "x"]))
        #expect(AppEnvironment.isRunningUnitTests(environment: ["XCTestBundlePath": "x"]))
        #expect(!AppEnvironment.isRunningUnitTests(environment: [:]))
    }

    /// Removes `<UUID>/` above a test FileStore root (`<UUID>/StudyReader`).
    private func removeParent(of fileStore: FileStore) {
        try? FileManager.default.removeItem(at: fileStore.rootURL.deletingLastPathComponent())
    }
}
