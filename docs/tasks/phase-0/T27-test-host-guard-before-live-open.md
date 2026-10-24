# T27: Decide on the test host before any library is opened

- **Phase:** 0 (fix from second bug hunt `docs/bugs/phase-0-second-pass.md` L1, user decision 2026-10-24)
- **Agent:** ui-builder
- **Depends on:** T26
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md (last Decision bullet, amendment "2026-10-24, second bug hunt L1")
- **Visual check needed:** no

## Goal
Today the app picks the in-memory library from one signal: the XCTest environment variables. If Xcode renames them, the test host's `LaunchView.task` runs `defaultFactory()`, takes `live()` and opens and migrates the user's real library. Only afterwards does `hostedProcessIsDetected` fail. That is the reverse of what ADR-0011 promised, and while a `v3` migration is being written it would apply the uncommitted `v3` to the real library.

This task adds two more signals that don't depend on those variable names. All three are read **once at launch, before anything opens a library**. Any one of them selects the in-memory library. The real library opens only when all three are absent. Each signal gets its own guard test against the real process. So if one signal breaks, a test names it, and the other two still keep the real library closed.

The three signals (fields of `AppEnvironment.TestHostSignals`):

| Field | Source | Set by |
|---|---|---|
| `xctestEnvironment` | `XCTestConfigurationFilePath` or `XCTestBundlePath` in the environment (existing `isRunningUnitTests`) | Xcode |
| `inMemoryRequested` | environment variable `STUDYREADER_IN_MEMORY` present (any value), or launch argument `-StudyReaderInMemory` | **our** `project.yml` test action; UI tests or manual runs for the argument |
| `xctestLibraryLoaded` | a loaded dyld image whose file name starts with `XCTest` or `libXCTest` (for example `libXCTestBundleInject.dylib`, which Xcode inserts into the host before `main()`) | Xcode's test-bundle injection |

There's no schema change and no migration.

## Files to touch
- `project.yml` (modify: the `schemes.StudyReader.test` block only)
- `StudyReader/App/AppEnvironment.swift` (modify: add the signal types and functions below; remove `usesInMemoryLibrary(environment:arguments:)`)
- `StudyReader/App/AppLaunchModel.swift` (modify: `defaultFactory()` and one new static function; nothing else)
- `StudyReader/App/StudyReaderApp.swift` (modify: add `init()`)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift` (modify: rewrite two tests, add four)

## project.yml change (exact)
Replace the `test:` block of `schemes: StudyReader:` with this. Leave `build:` and `run:` exactly as they are. The run action must not get the variable or the argument, or every normal launch would use a temporary library:
```yaml
    test:
      config: Debug
      targets:
        - StudyReaderTests
      shouldUseLaunchSchemeArgsEnv: false
      environmentVariables:
        STUDYREADER_IN_MEMORY: "1"
```
`shouldUseLaunchSchemeArgsEnv: false` is required. Without it, Xcode's test action reuses the run action's (empty) environment and ignores this one. Don't edit `.xcodeproj`. `./scripts/test.sh` runs `xcodegen generate` itself.

## Interfaces to produce

### `AppEnvironment.swift`
Add `import MachO` below `import Foundation`. Keep `isRunningUnitTests(environment:)` and `inMemoryLaunchArgument` exactly as they are. **Delete** `usesInMemoryLibrary(environment:arguments:)` and its doc comment; `TestHostSignals.usesInMemoryLibrary` replaces it. Add inside `struct AppEnvironment`, after `inMemoryLaunchArgument`:
```swift
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
```
If `String(validatingCString:)` isn't available or warns, use `String(cString: $0)` inside the same `flatMap` and say so in your report. Don't add any other signal (for example `Bundle.allBundles` or `NSClassFromString`). Those only become true when the test bundle loads, which can be after the launch decision.

### `AppLaunchModel.swift`
Replace `defaultFactory()` and add `chooseEnvironment` directly below it. Don't change anything else (`init`, `start()`, `failureMessage`, `genericFailureMessage`):
```swift
    nonisolated static func defaultFactory() throws -> AppEnvironment {
        try chooseEnvironment(
            for: AppEnvironment.launchTestHostSignals,
            live: { try AppEnvironment.live() },
            inMemory: { try AppEnvironment.inMemory() }
        )
    }

    /// The only place that chooses the library (ADR-0011). Any test-host signal → `inMemory`.
    /// `live` runs only when every signal is false.
    nonisolated static func chooseEnvironment(
        for signals: AppEnvironment.TestHostSignals,
        live: () throws -> AppEnvironment,
        inMemory: () throws -> AppEnvironment
    ) rethrows -> AppEnvironment {
        if signals.usesInMemoryLibrary {
            Log.app.info("Using the in-memory library (xctestEnvironment: \(signals.xctestEnvironment, privacy: .public), inMemoryRequested: \(signals.inMemoryRequested, privacy: .public), xctestLibraryLoaded: \(signals.xctestLibraryLoaded, privacy: .public))")
            return try inMemory()
        }
        return try live()
    }
```
Also update the doc comment on `init(makeEnvironment:)` to: `/// Default factory: defaultFactory() (in-memory library when any test-host signal is set, the user's library otherwise).`

### `StudyReaderApp.swift`
Add this initializer inside `struct StudyReaderApp`, below the `@State` property. Change nothing else:
```swift
    init() {
        // Read the test-host signals before anything can open a library (ADR-0011).
        _ = AppEnvironment.launchTestHostSignals
    }
```

## Tests (`AppEnvironmentTests`; the struct name is the test filter)
Never call `AppEnvironment.live()` in a test. Keep `makeCreatesOnDiskDatabase`, `inMemoryEnvironmentIsEmpty`, `detectsTestHost`, `defaultFactoryUsesTemporaryLibraryInTests`, `removeStaleInMemoryFoldersKeepsRecentOnes` and `testFileStoreRemoveOnlyDeletesTestFolders` unchanged.

Add one private helper to the suite:
```swift
    private typealias Signals = AppEnvironment.TestHostSignals
    private enum Pick: Error { case live, inMemory }
```

**Guard tests against the real process.** Each signal has its own test, so a failure names the broken signal.
1. **`hostedProcessIsDetected`** (rewrite; keep its doc comment, and add the sentence "The other two signals still keep the real library closed."):
   - `#expect(AppEnvironment.isRunningUnitTests())`
   - `#expect(AppEnvironment.launchTestHostSignals.xctestEnvironment)`
   - `#expect(AppEnvironment.launchTestHostSignals.usesInMemoryLibrary)`
2. **`testSchemeSetsInMemoryVariable`** (new). Doc comment: `/// If this fails, project.yml's test action no longer passes STUDYREADER_IN_MEMORY (check shouldUseLaunchSchemeArgsEnv: false).`
   - `#expect(ProcessInfo.processInfo.environment[AppEnvironment.inMemoryEnvironmentVariable] != nil)`
   - `#expect(AppEnvironment.launchTestHostSignals.inMemoryRequested)`
3. **`xctestLibraryWasLoadedAtLaunch`** (new). Doc comment: `/// If this fails, Xcode no longer injects an XCTest library before launch. The message lists the XCTest images loaded now.`
   - `let xctestImages = AppEnvironment.loadedImagePaths().filter { $0.localizedCaseInsensitiveContains("xctest") }`
   - `#expect(AppEnvironment.launchTestHostSignals.xctestLibraryLoaded, "XCTest images loaded now: \(xctestImages)")`

**Pure tests with injected inputs.** Pass `environment: [:]`, `arguments: []` and `imagePaths: []` for every input a bullet doesn't name, so the test process's own environment and images never leak in:

4. **`inMemoryLaunchArgumentIsHonoured`** (rewrite with `testHostSignals`):
   - `testHostSignals(environment: [:], arguments: ["StudyReader", "-StudyReaderInMemory"], imagePaths: []).usesInMemoryLibrary` is true;
   - `testHostSignals(environment: [:], arguments: ["StudyReader"], imagePaths: []).usesInMemoryLibrary` is false;
   - `testHostSignals(environment: ["XCTestBundlePath": "x"], arguments: [], imagePaths: []).usesInMemoryLibrary` is true.
5. **`testHostSignalsReadEachInput`** (new). Each line is `#expect(AppEnvironment.testHostSignals(...) == Signals(...))`:
   - `environment: [:], arguments: ["StudyReader"], imagePaths: ["/usr/lib/libSystem.B.dylib"]` → all three false, and `.usesInMemoryLibrary` is false (separate `#expect`);
   - `environment: ["XCTestConfigurationFilePath": "x"]` → only `xctestEnvironment`;
   - `environment: ["STUDYREADER_IN_MEMORY": "1"]` → only `inMemoryRequested`;
   - `environment: ["STUDYREADER_IN_MEMORY": "0"]` → only `inMemoryRequested` (presence counts, not the value; this fails closed);
   - `arguments: ["StudyReader", "-StudyReaderInMemory"]` → only `inMemoryRequested`;
   - `imagePaths: ["/Applications/Xcode.app/Contents/Developer/usr/lib/libXCTestBundleInject.dylib"]` → only `xctestLibraryLoaded`;
   - each of the three single-signal values above has `.usesInMemoryLibrary == true` (three `#expect`s).
6. **`detectsXCTestLibrary`** (new). `xctestLibraryIsLoaded(imagePaths: [p])` for each path:
   - true: `/Applications/Xcode.app/Contents/Developer/usr/lib/libXCTestBundleInject.dylib`, `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Versions/A/XCTest`, `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestCore.framework/Versions/A/XCTestCore`;
   - false: `/Users/me/Build/Products/Debug/StudyReader.app/Contents/MacOS/StudyReader`, `/usr/lib/libSystem.B.dylib`, `/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI`, `/Users/me/Build/Products/Debug/StudyReader.app/Contents/PlugIns/StudyReaderTests.xctest/Contents/MacOS/StudyReaderTests` (the test bundle itself loads later and doesn't count), `/Users/me/XCTestNotes/libNotes.dylib` (only the file name counts);
   - `xctestLibraryIsLoaded(imagePaths: [])` is false.
7. **`factoryChoiceFollowsSignals`** (new). Uses throwing closures, so no environment is created and `live()` is never called:
   - `let none = Signals(xctestEnvironment: false, inMemoryRequested: false, xctestLibraryLoaded: false)`;
   - `#expect(throws: Pick.live) { try AppLaunchModel.chooseEnvironment(for: none, live: { throw Pick.live }, inMemory: { throw Pick.inMemory }) }`;
   - for each of the three single-signal values (exactly one field true), the same call `#expect(throws: Pick.inMemory)`.

If test 2 or test 3 fails when you first run the suite, don't change the signal, the filter or the expectation to make it pass. Report BLOCKED with the full failure message (test 3's message lists the loaded XCTest images). The architect decides the replacement signal.

## Acceptance criteria
1. `project.yml`'s test action has `shouldUseLaunchSchemeArgsEnv: false` and `environmentVariables: STUDYREADER_IN_MEMORY: "1"`. The run and build actions are unchanged and have no environment variables or arguments. → code review of the diff + test `AppEnvironmentTests/testSchemeSetsInMemoryVariable`
2. The XCTest environment variables are seen at launch. → test `AppEnvironmentTests/hostedProcessIsDetected`
3. The XCTest injection library is seen at launch. → test `AppEnvironmentTests/xctestLibraryWasLoadedAtLaunch`
4. Each input sets exactly its own signal, and any single signal selects the in-memory library. → tests `AppEnvironmentTests/testHostSignalsReadEachInput`, `AppEnvironmentTests/inMemoryLaunchArgumentIsHonoured`
5. Only XCTest library file names match; the app, system libraries, the test bundle and directory names don't. → test `AppEnvironmentTests/detectsXCTestLibrary`
6. `live` runs only when all signals are false; any one signal runs `inMemory` and never `live`. → test `AppEnvironmentTests/factoryChoiceFollowsSignals`
7. The default factory still returns a temporary library inside tests. → test `AppEnvironmentTests/defaultFactoryUsesTemporaryLibraryInTests` (unchanged)
8. `defaultFactory()` reads only `AppEnvironment.launchTestHostSignals` and goes through `chooseEnvironment`. `StudyReaderApp.init()` reads `launchTestHostSignals`. `usesInMemoryLibrary(environment:arguments:)` is gone, and nothing else calls `live()`. → code review of the diff
9. Mutation checks, done by the reviewer by reading the code, not by running it:
   - a misspelled key in `isRunningUnitTests` fails `hostedProcessIsDetected`, while `defaultFactory` still picks in-memory through the other two signals;
   - removing the `environmentVariables` from `project.yml` fails `testSchemeSetsInMemoryVariable`;
   - dropping any one term from `usesInMemoryLibrary` fails `testHostSignalsReadEachInput`;
   - swapping the branches in `chooseEnvironment` fails `factoryChoiceFollowsSignals`.
10. The full suite passes with no new warnings. → test-runner (`./scripts/test.sh`)

## What the tests can't check
- **That the signals are read before the test bundle loads.** `xctestEnvironment` and `inMemoryRequested` come from the environment and arguments, which are fixed when the process starts, so their guard tests are exact. `xctestLibraryLoaded` relies on `StudyReaderApp.init()` running before Xcode loads the test bundle (which links XCTest). If that order ever changed, `xctestLibraryWasLoadedAtLaunch` could pass even without the injection library. This only weakens that one guard, not the decision.
- **That a normal launch (Finder, Dock, Xcode Run) still opens the real library.** No test may call `live()`. The reviewer checks it by reading: the run action has no variable or argument, the app target doesn't link XCTest, and a normal launch has no XCTest variables. A false positive would quietly put the user's work in a temporary library that gets deleted after an hour. In the unified log it shows as "Using the in-memory library".
- **All three signals failing at once.** Then the host would open the real library before the guard tests ran, and the tests would only report it afterwards. ADR-0011 now says so.
- **Xcode Previews** (unverified in the bug report) aren't covered by this task.

## Out of scope
- Any schema, migration, `AppDatabase` or `FileStore` change.
- L2 (the clock that `inMemory(now:)` uses for cleanup) and the other backlog items.
- Changing the XCTest variable names in `isRunningUnitTests`, `inMemoryLaunchArgument`, `start()`, or `LaunchView`.
- Adding a UI indicator for the temporary library, XCUITest targets, or a Previews guard.
- Editing ADR-0011 (already amended for this task), `scripts/`, or `.xcodeproj`.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
