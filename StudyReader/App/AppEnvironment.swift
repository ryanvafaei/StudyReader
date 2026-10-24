import Foundation
import MachO

/// Long-lived dependencies, created once at launch. Feature models receive it in their initializers.
struct AppEnvironment: Sendable {
    let fileStore: FileStore
    let database: AppDatabase
    let now: any Now
    let categoryRepository: CategoryRepository
    let documentRepository: DocumentRepository

    /// Builds the repositories from `database`.
    init(fileStore: FileStore, database: AppDatabase, now: any Now) {
        self.fileStore = fileStore
        self.database = database
        self.now = now
        self.categoryRepository = CategoryRepository(database: database)
        self.documentRepository = DocumentRepository(database: database)
    }

    /// The user's library: FileStore.applicationSupport(), then make(fileStore:).
    static func live() throws -> AppEnvironment {
        try make(fileStore: FileStore.applicationSupport())
    }

    /// On-disk database in the given FileStore (AppDatabase.makeShared), SystemNow by default.
    static func make(fileStore: FileStore, now: any Now = SystemNow()) throws -> AppEnvironment {
        let database = try AppDatabase.makeShared(fileStore: fileStore)
        return AppEnvironment(fileStore: fileStore, database: database, now: now)
    }

    /// FileManager.default.temporaryDirectory/StudyReader-InMemory
    static var inMemoryParentURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "StudyReader-InMemory", directoryHint: .isDirectory)
    }

    /// Removes direct subfolders of `parent` whose creation date (URLResourceKey.creationDateKey) is earlier than `cutoff`.
    /// Missing `parent` is not an error. Each removal failure is ignored. Returns the number of folders removed.
    @discardableResult
    static func removeStaleInMemoryFolders(in parent: URL, olderThan cutoff: Date) -> Int {
        let keys: Set<URLResourceKey> = [.creationDateKey, .isDirectoryKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var removed = 0
        for child in children {
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  let created = values.creationDate,
                  created < cutoff else {
                continue
            }
            if (try? FileManager.default.removeItem(at: child)) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// AppDatabase.makeInMemory() plus a FileStore rooted at
    /// FileManager.default.temporaryDirectory/StudyReader-InMemory/<UUID>/StudyReader (directories created).
    /// Removes in-memory folders older than one hour first.
    static func inMemory(now: any Now = SystemNow()) throws -> AppEnvironment {
        let removed = removeStaleInMemoryFolders(in: inMemoryParentURL, olderThan: now().addingTimeInterval(-3600))
        if removed > 0 {
            Log.files.info("Removed \(removed, privacy: .public) stale in-memory libraries")
        }
        let root = inMemoryParentURL
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "StudyReader", directoryHint: .isDirectory)
        let fileStore = FileStore(rootURL: root)
        try fileStore.createRootDirectories()
        let database = try AppDatabase.makeInMemory()
        return AppEnvironment(fileStore: fileStore, database: database, now: now)
    }

    /// true when the process is a unit-test host: environment contains
    /// "XCTestConfigurationFilePath" or "XCTestBundlePath".
    static func isRunningUnitTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    /// Launch argument that forces the in-memory environment (ADR-0011). UI tests pass it via launchArguments.
    static let inMemoryLaunchArgument = "-StudyReaderInMemory"

    /// Environment variable that forces the in-memory environment. The test action in project.yml sets it (ADR-0011).
    static let inMemoryEnvironmentVariable = "STUDYREADER_IN_MEMORY"

    /// Independent signals that this process is a test host (ADR-0011). Any one of them selects the in-memory library.
    struct TestHostSignals: Sendable, Equatable {
        /// isRunningUnitTests(environment:): Xcode's XCTest environment variables.
        var xctestEnvironment: Bool
        /// inMemoryEnvironmentVariable is set (any value), or the arguments contain inMemoryLaunchArgument.
        var inMemoryRequested: Bool
        /// xctestLibraryIsLoaded(imagePaths:): Xcode's test-bundle injection library is in the process.
        var xctestLibraryLoaded: Bool

        /// true when any signal is set. Only when this is false may the user's library be opened.
        var usesInMemoryLibrary: Bool {
            xctestEnvironment || inMemoryRequested || xctestLibraryLoaded
        }
    }

    /// true when an image's file name (last path component) starts with "XCTest" or "libXCTest",
    /// for example libXCTestBundleInject.dylib, XCTest, XCTestCore. Directory names don't count.
    static func xctestLibraryIsLoaded(imagePaths: [String]) -> Bool {
        imagePaths.contains { path in
            let name = URL(filePath: path).lastPathComponent
            return name.hasPrefix("XCTest") || name.hasPrefix("libXCTest")
        }
    }

    /// Paths of the images (executable, dylibs, frameworks) dyld has loaded into this process.
    static func loadedImagePaths() -> [String] {
        (0..<_dyld_image_count()).compactMap { index in
            _dyld_get_image_name(index).flatMap { String(validatingCString: $0) }
        }
    }

    /// Pure: reads the three signals from the given inputs.
    static func testHostSignals(
        environment: [String: String],
        arguments: [String],
        imagePaths: [String]
    ) -> TestHostSignals {
        TestHostSignals(
            xctestEnvironment: isRunningUnitTests(environment: environment),
            inMemoryRequested: environment[inMemoryEnvironmentVariable] != nil
                || arguments.contains(inMemoryLaunchArgument),
            xctestLibraryLoaded: xctestLibraryIsLoaded(imagePaths: imagePaths)
        )
    }

    /// This process's signals, read once. StudyReaderApp.init() reads it first, before any library is opened
    /// and before Xcode loads the test bundle, so it shows the process as it was launched.
    static let launchTestHostSignals: TestHostSignals = testHostSignals(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments,
        imagePaths: loadedImagePaths()
    )
}
