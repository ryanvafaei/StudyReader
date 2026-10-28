import Foundation
import Testing
@testable import StudyReader

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    private typealias Signals = AppEnvironment.TestHostSignals
    private enum Pick: Error { case live, inMemory }

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
    /// The other two signals still keep the real library closed.
    @Test func hostedProcessIsDetected() {
        #expect(AppEnvironment.isRunningUnitTests())
        #expect(AppEnvironment.launchTestHostSignals.xctestEnvironment)
        #expect(AppEnvironment.launchTestHostSignals.usesInMemoryLibrary)
    }

    /// If this fails, project.yml's test action no longer passes STUDYREADER_IN_MEMORY (check shouldUseLaunchSchemeArgsEnv: false).
    @Test func testSchemeSetsInMemoryVariable() {
        #expect(ProcessInfo.processInfo.environment[AppEnvironment.inMemoryEnvironmentVariable] != nil)
        #expect(AppEnvironment.launchTestHostSignals.inMemoryRequested)
    }

    /// If this fails, Xcode no longer injects an XCTest library before launch. The message lists the XCTest images loaded now.
    @Test func xctestLibraryWasLoadedAtLaunch() {
        let xctestImages = AppEnvironment.loadedImagePaths().filter { $0.localizedCaseInsensitiveContains("xctest") }
        #expect(AppEnvironment.launchTestHostSignals.xctestLibraryLoaded, "XCTest images loaded now: \(xctestImages)")
    }

    @Test func inMemoryLaunchArgumentIsHonoured() {
        #expect(AppEnvironment.testHostSignals(environment: [:], arguments: ["StudyReader", "-StudyReaderInMemory"], imagePaths: []).usesInMemoryLibrary)
        #expect(!AppEnvironment.testHostSignals(environment: [:], arguments: ["StudyReader"], imagePaths: []).usesInMemoryLibrary)
        #expect(AppEnvironment.testHostSignals(environment: ["XCTestBundlePath": "x"], arguments: [], imagePaths: []).usesInMemoryLibrary)
    }

    @Test func testHostSignalsReadEachInput() {
        let system = "/usr/lib/libSystem.B.dylib"
        let none = AppEnvironment.testHostSignals(environment: [:], arguments: ["StudyReader"], imagePaths: [system])
        #expect(none == Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: false))
        #expect(!none.usesInMemoryLibrary)

        let xctestEnvironment = AppEnvironment.testHostSignals(environment: ["XCTestConfigurationFilePath": "x"], arguments: [], imagePaths: [])
        #expect(xctestEnvironment == Signals(xctestEnvironment: true, inMemoryRequested: false, xctestLibraryLoaded: false))

        let variableOne = AppEnvironment.testHostSignals(environment: ["STUDYREADER_IN_MEMORY": "1"], arguments: [], imagePaths: [])
        #expect(variableOne == Signals(xctestEnvironment: false, inMemoryRequested: true, xctestLibraryLoaded: false))

        // Presence counts, not the value. This fails closed.
        let variableZero = AppEnvironment.testHostSignals(environment: ["STUDYREADER_IN_MEMORY": "0"], arguments: [], imagePaths: [])
        #expect(variableZero == Signals(xctestEnvironment: false, inMemoryRequested: true, xctestLibraryLoaded: false))

        let argument = AppEnvironment.testHostSignals(environment: [:], arguments: ["StudyReader", "-StudyReaderInMemory"], imagePaths: [])
        #expect(argument == Signals(xctestEnvironment: false, inMemoryRequested: true, xctestLibraryLoaded: false))

        let injected = AppEnvironment.testHostSignals(
            environment: [:],
            arguments: [],
            imagePaths: ["/Applications/Xcode.app/Contents/Developer/usr/lib/libXCTestBundleInject.dylib"]
        )
        #expect(injected == Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: true))

        #expect(xctestEnvironment.usesInMemoryLibrary)
        #expect(variableOne.usesInMemoryLibrary)
        #expect(injected.usesInMemoryLibrary)
    }

    @Test func detectsXCTestLibrary() {
        let truePaths = [
            "/Applications/Xcode.app/Contents/Developer/usr/lib/libXCTestBundleInject.dylib",
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Versions/A/XCTest",
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestCore.framework/Versions/A/XCTestCore",
        ]
        for path in truePaths {
            #expect(AppEnvironment.xctestLibraryIsLoaded(imagePaths: [path]), "\(path)")
        }

        let falsePaths = [
            "/Users/me/Build/Products/Debug/StudyReader.app/Contents/MacOS/StudyReader",
            "/usr/lib/libSystem.B.dylib",
            "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI",
            // The test bundle itself loads after the launch decision, and only its file name would count.
            "/Users/me/Build/Products/Debug/StudyReader.app/Contents/PlugIns/StudyReaderTests.xctest/Contents/MacOS/StudyReaderTests",
            // Only the file name counts, not the directory names.
            "/Users/me/XCTestNotes/libNotes.dylib",
        ]
        for path in falsePaths {
            #expect(!AppEnvironment.xctestLibraryIsLoaded(imagePaths: [path]), "\(path)")
        }

        #expect(!AppEnvironment.xctestLibraryIsLoaded(imagePaths: []))
    }

    /// Throwing closures stand in for live() and inMemory(), so no environment is created.
    @Test func factoryChoiceFollowsSignals() {
        let none = Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: false)
        #expect(throws: Pick.live) {
            try AppLaunchModel.chooseEnvironment(for: none, live: { throw Pick.live }, inMemory: { throw Pick.inMemory })
        }

        let singles = [
            Signals(xctestEnvironment: true, inMemoryRequested: false, xctestLibraryLoaded: false),
            Signals(xctestEnvironment: false, inMemoryRequested: true, xctestLibraryLoaded: false),
            Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: true),
        ]
        for signals in singles {
            #expect(throws: Pick.inMemory) {
                try AppLaunchModel.chooseEnvironment(for: signals, live: { throw Pick.live }, inMemory: { throw Pick.inMemory })
            }
        }
    }

    @Test func resetsEphemeralSettingsOnlyForInMemoryLaunchesOutsideUnitTests() {
        #expect(AppLaunchModel.shouldResetEphemeralSettings(
            Signals(xctestEnvironment: false, inMemoryRequested: true, xctestLibraryLoaded: false)))
        #expect(!AppLaunchModel.shouldResetEphemeralSettings(
            Signals(xctestEnvironment: true, inMemoryRequested: true, xctestLibraryLoaded: false)))
        #expect(!AppLaunchModel.shouldResetEphemeralSettings(
            Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: false)))
        #expect(!AppLaunchModel.shouldResetEphemeralSettings(
            Signals(xctestEnvironment: true, inMemoryRequested: false, xctestLibraryLoaded: false)))
    }

    @Test func defaultFactoryUsesTemporaryLibraryInTests() throws {
        let environment = try AppLaunchModel.defaultFactory()
        defer { TestFileStore.remove(environment.fileStore) }
        let libraryStore = try FileStore.applicationSupport()
        let temporaryPath = FileManager.default.temporaryDirectory.path(percentEncoded: false)

        #expect(environment.fileStore.rootURL.path(percentEncoded: false).hasPrefix(temporaryPath))
        #expect(environment.fileStore != libraryStore)
    }

    /// A preview process must never open the user's library (ADR-0011 amendment, T31).
    @Test func previewsSelectInMemoryLibrary() {
        let signals = AppEnvironment.testHostSignals(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"], arguments: [], imagePaths: [])
        #expect(signals.runningForPreviews)
        #expect(signals.usesInMemoryLibrary)
    }

    /// Only the value "1" counts. Any other value, or no variable, leaves the preview signal off.
    @Test func previewsVariableMustBeOne() {
        let zero = AppEnvironment.testHostSignals(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "0"], arguments: [], imagePaths: [])
        #expect(!zero.runningForPreviews)

        let absent = AppEnvironment.testHostSignals(environment: [:], arguments: ["StudyReader"], imagePaths: [])
        #expect(!absent.runningForPreviews)
        #expect(!absent.usesInMemoryLibrary)
    }

    @Test func chooseEnvironmentUsesInMemoryForPreviews() throws {
        let signals = Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: false, runningForPreviews: true)
        let environment = try AppLaunchModel.chooseEnvironment(
            for: signals,
            live: { Issue.record("live called"); throw CancellationError() },
            inMemory: { try AppEnvironment.inMemory() }
        )
        defer { TestFileStore.remove(environment.fileStore) }

        #expect(environment.fileStore.rootURL.path(percentEncoded: false).hasPrefix(FileManager.default.temporaryDirectory.path(percentEncoded: false)))
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
