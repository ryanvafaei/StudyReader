# T08: AppEnvironment (dependency container) and launch wiring

- **Phase:** 0
- **Agent:** ui-builder
- **Depends on:** T01, T07
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md
- **Visual check needed:** yes

## Goal
Create `AppEnvironment`, the single place that builds the app's long-lived dependencies (FileStore, AppDatabase, clock, repositories), open it at launch, and pass it into `RootModel`. Show an error screen if the library can't be opened. During hosted test runs, use an in-memory database so tests never touch the user's library (ADR-0011). Completes epic E0.1/E0.2 wiring.

Read first: ARCHITECTURE §1 rules, §3, ADR-0011. Read `StudyReaderApp.swift`, `RootView.swift`, `RootModel.swift` (T01), `AppDatabase.swift`, `FileStore.swift`, `Now.swift`, and the two repositories.

## Files to touch
- `StudyReader/App/AppEnvironment.swift` (new)
- `StudyReader/App/AppLaunchModel.swift` (new)
- `StudyReader/App/LaunchView.swift` (new)
- `StudyReader/App/StudyReaderApp.swift` (modify)
- `StudyReader/App/RootView.swift` (modify)
- `StudyReader/App/RootModel.swift` (modify)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift` (new)
- `StudyReaderTests/AppTests/AppLaunchModelTests.swift` (new)
- `StudyReaderTests/AppTests/RootModelTests.swift` (new)

## Interfaces to produce

```swift
// AppEnvironment.swift
import Foundation

/// Long-lived dependencies, created once at launch. Feature models receive it in their initializers.
struct AppEnvironment: Sendable {
    let fileStore: FileStore
    let database: AppDatabase
    let now: any Now
    let categoryRepository: CategoryRepository
    let documentRepository: DocumentRepository

    /// Builds the repositories from `database`.
    init(fileStore: FileStore, database: AppDatabase, now: any Now)

    /// The user's library: FileStore.applicationSupport(), then make(fileStore:).
    static func live() throws -> AppEnvironment

    /// On-disk database in the given FileStore (AppDatabase.makeShared), SystemNow by default.
    static func make(fileStore: FileStore, now: any Now = SystemNow()) throws -> AppEnvironment

    /// AppDatabase.makeInMemory() plus a FileStore rooted at
    /// FileManager.default.temporaryDirectory/StudyReader-InMemory/<UUID>/StudyReader (directories created).
    static func inMemory(now: any Now = SystemNow()) throws -> AppEnvironment

    /// true when the process is a unit-test host: environment contains
    /// "XCTestConfigurationFilePath" or "XCTestBundlePath".
    static func isRunningUnitTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool
}

// AppLaunchModel.swift
import Observation

@MainActor @Observable
final class AppLaunchModel {
    enum State {
        case loading
        case ready(AppEnvironment)
        case failed(message: String)
    }
    private(set) var state: State = .loading

    /// Default factory: AppEnvironment.isRunningUnitTests() ? AppEnvironment.inMemory() : AppEnvironment.live()
    init(makeEnvironment: @escaping @Sendable () throws -> AppEnvironment = AppLaunchModel.defaultFactory)
    nonisolated static func defaultFactory() throws -> AppEnvironment

    /// Runs the factory once. Success → .ready; error → .failed(message: error.localizedDescription)
    /// and logs via Log.app (no paths or user data in the log). Calling start() again when not .loading does nothing.
    func start()
}

// RootModel.swift (modify)
@MainActor @Observable
final class RootModel {
    let environment: AppEnvironment
    var selection: SidebarItem? = .library
    init(environment: AppEnvironment)
}

// RootView.swift (modify)
struct RootView: View {
    init(environment: AppEnvironment)   // _model = State(initialValue: RootModel(environment: environment))
    // body unchanged from T01
}

// LaunchView.swift
struct LaunchView: View {
    let model: AppLaunchModel
    // switch model.state:
    //   .loading  → ProgressView("Opening library…")
    //   .ready(let env) → RootView(environment: env)
    //   .failed(let message) → ContentUnavailableView {
    //        Label("Couldn't open the library", systemImage: "exclamationmark.triangle")
    //     } description: { Text(message) }
    // .task { model.start() }
}

// StudyReaderApp.swift (modify)
@main
struct StudyReaderApp: App {
    @State private var launchModel = AppLaunchModel()
    var body: some Scene {
        Window("StudyReader", id: "main") { LaunchView(model: launchModel) }
            .defaultSize(width: 1100, height: 720)
    }
}
```
Rules: no `Date()` outside `SystemNow`; views don't touch the database; all new user-facing strings go through the String Catalog (SwiftUI string literals are fine); no other dependencies in `AppEnvironment` yet (later tasks add services here).

## Acceptance criteria
1. `AppEnvironment.make(fileStore: TestFileStore.make())` creates the database file at `fileStore.databaseURL`, and `categoryRepository.fetchAll()` returns 5 categories. → test `AppEnvironmentTests/makeCreatesOnDiskDatabase`
2. `AppEnvironment.inMemory()` returns an environment whose `documentRepository.fetchAll()` is empty and whose FileStore root exists in the temporary directory. → test `AppEnvironmentTests/inMemoryEnvironmentIsEmpty`
3. `isRunningUnitTests` is true for `["XCTestConfigurationFilePath": "x"]` and for `["XCTestBundlePath": "x"]`, false for `[:]`. → test `AppEnvironmentTests/detectsTestHost`
4. `AppLaunchModel` with a factory returning `inMemory()` reaches `.ready` after `start()`. → test `AppLaunchModelTests/startBecomesReady`
5. With a throwing factory (a test error whose `errorDescription` is "Disk full"), state becomes `.failed(message: "Disk full")`; a second `start()` doesn't call the factory again (count calls with a `Mutex<Int>` or an actor). → test `AppLaunchModelTests/startReportsFailureOnce`
6. `RootModel(environment:)` starts with `selection == .library`. → test `RootModelTests/defaultsToLibrary`
7. Visual check: delete nothing; build and run the app. The same window as T01 appears (sidebar with 6 items, placeholder detail). Then in Finder open `~/Library/Containers/com.ryanvafaei.StudyReader/Data/Library/Application Support/StudyReader/` and confirm `StudyReader.sqlite` (plus `-wal`/`-shm`) and a `Documents` folder exist. If macOS asks whether StudyReader may access data from other apps, allow it and note that in the review log.

Tests never call `AppEnvironment.live()`.

## Out of scope
- Launch-time cleanup of orphan folders and re-queuing extraction (Phase 1).
- Menus, Settings scene, library UI (Phase 1).
- An `EnvironmentValues` entry for the environment; pass it through initializers.

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-23, Sonnet (effort medium): APPROVED. Tests 69/69, test-host uses in-memory DB, failure path not re-runnable. Minor: two tests leave temp dirs; DB opens on main thread (revisit if migrations get slow). Visual check pending.
