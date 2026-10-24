import Foundation
import Testing
@testable import StudyReader

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    @Test func makeCreatesOnDiskDatabase() async throws {
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }

        let environment = try AppEnvironment.make(fileStore: fileStore)
        let categories = try await environment.categoryRepository.fetchAll()

        #expect(FileManager.default.fileExists(atPath: fileStore.databaseURL.path(percentEncoded: false)))
        #expect(categories.count == 5)
    }

    @Test func inMemoryEnvironmentIsEmpty() async throws {
        let environment = try AppEnvironment.inMemory()
        defer { TestFileStore.remove(environment.fileStore) }
        let documents = try await environment.documentRepository.fetchAll()
        let rootPath = environment.fileStore.rootURL.path(percentEncoded: false)
        let temporaryPath = FileManager.default.temporaryDirectory.path(percentEncoded: false)

        #expect(documents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: rootPath))
        #expect(rootPath.hasPrefix(temporaryPath))
    }

    @Test func detectsTestHost() {
        #expect(AppEnvironment.isRunningUnitTests(environment: ["XCTestConfigurationFilePath": "x"]))
        #expect(AppEnvironment.isRunningUnitTests(environment: ["XCTestBundlePath": "x"]))
        #expect(!AppEnvironment.isRunningUnitTests(environment: [:]))
    }

    /// If this fails, Xcode changed how it launches the test host. Fix detection before running any other test: the app would open the real library.
    @Test func hostedProcessIsDetected() {
        #expect(AppEnvironment.isRunningUnitTests())
        #expect(AppEnvironment.usesInMemoryLibrary())
    }

    @Test func inMemoryLaunchArgumentIsHonoured() {
        #expect(AppEnvironment.usesInMemoryLibrary(environment: [:], arguments: ["StudyReader", "-StudyReaderInMemory"]))
        #expect(!AppEnvironment.usesInMemoryLibrary(environment: [:], arguments: ["StudyReader"]))
        #expect(AppEnvironment.usesInMemoryLibrary(environment: ["XCTestBundlePath": "x"], arguments: []))
    }

    @Test func defaultFactoryUsesTemporaryLibraryInTests() throws {
        let environment = try AppLaunchModel.defaultFactory()
        defer { TestFileStore.remove(environment.fileStore) }
        let libraryStore = try FileStore.applicationSupport()
        let temporaryPath = FileManager.default.temporaryDirectory.path(percentEncoded: false)

        #expect(environment.fileStore.rootURL.path(percentEncoded: false).hasPrefix(temporaryPath))
        #expect(environment.fileStore != libraryStore)
    }

    @Test func removeStaleInMemoryFoldersKeepsRecentOnes() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appending(path: "StudyReaderTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: base) }
        let parent = base.appending(path: "parent", directoryHint: .isDirectory)
        let old = parent.appending(path: "old", directoryHint: .isDirectory)
        let recent = parent.appending(path: "new", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: old, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recent, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: old.path(percentEncoded: false)
        )

        let removed = AppEnvironment.removeStaleInMemoryFolders(
            in: parent,
            olderThan: Date(timeIntervalSince1970: 1_750_000_000)
        )

        #expect(removed == 1)
        #expect(!fileManager.fileExists(atPath: old.path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: recent.path(percentEncoded: false)))

        let missing = base.appending(path: "missing", directoryHint: .isDirectory)
        #expect(AppEnvironment.removeStaleInMemoryFolders(in: missing, olderThan: Date()) == 0)
    }

    @Test func testFileStoreRemoveOnlyDeletesTestFolders() throws {
        let fileManager = FileManager.default

        let store = TestFileStore.make()
        try store.createRootDirectories()
        TestFileStore.remove(store)
        #expect(!fileManager.fileExists(atPath: store.rootURL.deletingLastPathComponent().path(percentEncoded: false)))

        let foreignBase = fileManager.temporaryDirectory
            .appending(path: "StudyReaderTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: foreignBase) }
        let foreign = FileStore(rootURL: foreignBase.appending(path: "Other", directoryHint: .isDirectory))
        try fileManager.createDirectory(at: foreign.rootURL, withIntermediateDirectories: true)
        TestFileStore.remove(foreign)
        #expect(fileManager.fileExists(atPath: foreign.rootURL.path(percentEncoded: false)))
    }
}
