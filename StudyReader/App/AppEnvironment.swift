import Foundation

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
}
