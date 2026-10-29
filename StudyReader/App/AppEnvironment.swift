import Foundation
import MachO

/// Long-lived dependencies, created once at launch. Feature models receive it in their initializers.
struct AppEnvironment: Sendable {
    let fileStore: FileStore
    let database: AppDatabase
    let now: any Now
    let categoryRepository: CategoryRepository
    let documentRepository: DocumentRepository
    let highlightRepository: HighlightRepository
    let reviewCardRepository: ReviewCardRepository
    let tagRepository: TagRepository
    let notesRepository: NotesRepository
    let exportRepository: ExportRepository
    let highlightService: HighlightService
    let documentTextRepository: DocumentTextRepository
    let extractionService: ExtractionService
    let importService: ImportService
    let searchService: SearchService
    let settingsStore: SettingsStore
    let sleeper: any Sleeper
    let httpClient: any HTTPClient
    let googleAuth: any GoogleAuthProviding
    /// The GoogleSignIn wrapper (also `googleAuth`) in the user's library; nil in tests and the in-memory library,
    /// which never touch GoogleSignIn or the keychain (ADR-0018).
    let googleSignIn: GoogleSignInAuth?
    let googleExportService: GoogleExportService
    let exportSyncScheduler: ExportSyncScheduler
    /// Whether `startBackgroundWork()` starts `exportSyncScheduler`. Only `live()` turns it on, so tests, previews and
    /// the in-memory library never export on their own.
    let runsExportSync: Bool
    /// Live note editors and reader tabs; quit flushes them (T93).
    let pendingWrites: PendingWrites

    /// Builds the repositories and services from `database`.
    init(
        fileStore: FileStore,
        database: AppDatabase,
        now: any Now,
        settingsStore: SettingsStore = .ephemeral(),
        sleeper: any Sleeper = SystemSleeper(),
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        googleAuth: any GoogleAuthProviding = UnconfiguredGoogleAuth(),
        googleSignIn: GoogleSignInAuth? = nil,
        networkMonitor: any NetworkPathMonitoring = SystemNetworkPathMonitor(),
        runsExportSync: Bool = false
    ) {
        self.runsExportSync = runsExportSync
        self.pendingWrites = PendingWrites()
        self.fileStore = fileStore
        self.database = database
        self.now = now
        self.settingsStore = settingsStore
        self.sleeper = sleeper
        self.httpClient = httpClient
        self.googleAuth = googleAuth
        self.googleSignIn = googleSignIn
        self.categoryRepository = CategoryRepository(database: database)
        self.documentRepository = DocumentRepository(database: database)
        self.highlightRepository = HighlightRepository(database: database)
        self.reviewCardRepository = ReviewCardRepository(database: database)
        self.tagRepository = TagRepository(database: database)
        self.notesRepository = NotesRepository(database: database)
        let exportRepository = ExportRepository(database: database)
        self.exportRepository = exportRepository
        let googleExportService = GoogleExportService(
            auth: googleAuth,
            http: httpClient,
            repository: exportRepository,
            settings: settingsStore,
            now: now,
            sleeper: sleeper,
            colorLabels: { HighlightColor.allCases.map { settingsStore.colorLabel(for: $0) } }
        )
        self.googleExportService = googleExportService
        self.exportSyncScheduler = ExportSyncScheduler(
            repository: exportRepository,
            exporter: googleExportService,
            network: networkMonitor,
            sleeper: sleeper
        )
        self.highlightService = HighlightService(
            highlights: self.highlightRepository,
            tags: self.tagRepository,
            fileStore: fileStore,
            now: now
        )
        self.documentTextRepository = DocumentTextRepository(database: database)
        self.searchService = SearchService(database: database)
        let extractionService = ExtractionService(database: database, fileStore: fileStore)
        self.extractionService = extractionService
        self.importService = ImportService(
            fileStore: fileStore,
            documents: self.documentRepository,
            categories: self.categoryRepository,
            covers: CoverService(fileStore: fileStore, documents: self.documentRepository),
            settings: settingsStore,
            now: now,
            extractionQueue: extractionService
        )
    }

    /// Re-queues documents whose extraction is pending or outdated (LibraryMaintenance). Call once after launch.
    func startBackgroundWork() async {
        let maintenance = LibraryMaintenance(database: database, fileStore: fileStore)
        let ids = (try? await maintenance.documentIdsNeedingExtraction()) ?? []
        for id in ids {
            await extractionService.enqueue(documentId: id)
        }
        Log.files.info("Re-queued \(ids.count, privacy: .public) extractions at launch")
        await googleSignIn?.restorePreviousSignIn()
        if runsExportSync {
            await exportSyncScheduler.start()
        }
    }

    /// The user's library: FileStore.applicationSupport(), then make(fileStore:now:settingsStore:googleSignIn:) with
    /// `.standard()` and the GoogleSignIn wrapper (inert when the build has no Google client ID).
    static func live() throws -> AppEnvironment {
        try make(
            fileStore: FileStore.applicationSupport(),
            settingsStore: .standard(),
            googleSignIn: GoogleSignInAuth(clientID: GoogleSignInAuth.bundleClientID),
            runsExportSync: true
        )
    }

    /// On-disk database in the given FileStore (AppDatabase.makeShared), SystemNow by default.
    /// `googleSignIn`, when given, is also the environment's `googleAuth`.
    static func make(
        fileStore: FileStore,
        now: any Now = SystemNow(),
        settingsStore: SettingsStore = .ephemeral(),
        googleSignIn: GoogleSignInAuth? = nil,
        runsExportSync: Bool = false
    ) throws -> AppEnvironment {
        let database = try AppDatabase.makeShared(fileStore: fileStore)
        // Private: the path contains the user's home folder. Redacted in the persisted log.
        Log.files.info("Library root \(fileStore.rootURL.path(percentEncoded: false), privacy: .private)")
        // Folders left by interrupted imports are removed before the library appears (ADR-0016).
        let removed = try? LibraryMaintenance(database: database, fileStore: fileStore).removeOrphanFolders()
        Log.files.info("Removed \(removed?.count ?? 0, privacy: .public) orphan document folders at launch")
        if let googleSignIn {
            return AppEnvironment(
                fileStore: fileStore,
                database: database,
                now: now,
                settingsStore: settingsStore,
                googleAuth: googleSignIn,
                googleSignIn: googleSignIn,
                runsExportSync: runsExportSync
            )
        }
        return AppEnvironment(
            fileStore: fileStore,
            database: database,
            now: now,
            settingsStore: settingsStore,
            runsExportSync: runsExportSync
        )
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
    /// Removes in-memory folders older than one hour by the wall clock (`SystemNow`), never by the injected `now`,
    /// so a test with a future clock can't delete the folders of tests still running (backlog L2).
    static func inMemory(now: any Now = SystemNow()) throws -> AppEnvironment {
        let removed = removeStaleInMemoryFolders(in: inMemoryParentURL, olderThan: SystemNow()().addingTimeInterval(-3600))
        if removed > 0 {
            Log.files.info("Removed \(removed, privacy: .public) stale in-memory libraries")
        }
        let root = inMemoryParentURL
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "StudyReader", directoryHint: .isDirectory)
        let fileStore = FileStore(rootURL: root)
        try fileStore.createRootDirectories()
        let database = try AppDatabase.makeInMemory()
        return AppEnvironment(fileStore: fileStore, database: database, now: now, settingsStore: .ephemeral())
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

    /// Environment variable Xcode sets in preview processes (ADR-0011 amendment, T31).
    static let previewsEnvironmentVariable = "XCODE_RUNNING_FOR_PREVIEWS"

    /// Independent signals that this process is a test host or an Xcode Preview (ADR-0011). Any one of them selects the in-memory library.
    struct TestHostSignals: Sendable, Equatable {
        /// isRunningUnitTests(environment:): Xcode's XCTest environment variables.
        var xctestEnvironment: Bool
        /// inMemoryEnvironmentVariable is set (any value), or the arguments contain inMemoryLaunchArgument.
        var inMemoryRequested: Bool
        /// xctestLibraryIsLoaded(imagePaths:): Xcode's test-bundle injection library is in the process.
        var xctestLibraryLoaded: Bool
        /// environment[previewsEnvironmentVariable] == "1". Only the value "1" counts.
        var runningForPreviews: Bool = false

        /// true when any signal is set. Only when this is false may the user's library be opened.
        var usesInMemoryLibrary: Bool {
            xctestEnvironment || inMemoryRequested || xctestLibraryLoaded || runningForPreviews
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

    /// Pure: reads the four signals from the given inputs.
    static func testHostSignals(
        environment: [String: String],
        arguments: [String],
        imagePaths: [String]
    ) -> TestHostSignals {
        TestHostSignals(
            xctestEnvironment: isRunningUnitTests(environment: environment),
            inMemoryRequested: environment[inMemoryEnvironmentVariable] != nil
                || arguments.contains(inMemoryLaunchArgument),
            xctestLibraryLoaded: xctestLibraryIsLoaded(imagePaths: imagePaths),
            runningForPreviews: environment[previewsEnvironmentVariable] == "1"
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
