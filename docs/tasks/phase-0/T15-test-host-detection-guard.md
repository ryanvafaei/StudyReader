# T15: Guard test-host detection and add an in-memory launch argument

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` M4)
- **Agent:** ui-builder
- **Depends on:** T14
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md (last Decision bullet, amended 2026-10-24)
- **Visual check needed:** no

## Goal
The app uses an in-memory library when it runs as a unit-test host. Detection relies on two environment variable names, and no test checks the real process. If Xcode renamed a variable, every test run would silently open and migrate the user's real library. Add a test that checks detection against the real environment, and an explicit launch argument `-StudyReaderInMemory` for UI tests and manual runs.

## Files to touch
- `StudyReader/App/AppEnvironment.swift` (modify: add `inMemoryLaunchArgument`, `usesInMemoryLibrary`)
- `StudyReader/App/AppLaunchModel.swift` (modify `defaultFactory` only)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift` (modify: add tests)

## Interfaces to produce
Add inside `struct AppEnvironment`:
```swift
    /// Launch argument that forces the in-memory environment (ADR-0011). UI tests pass it via launchArguments.
    static let inMemoryLaunchArgument = "-StudyReaderInMemory"

    /// true when isRunningUnitTests(environment:) is true, or `arguments` contains inMemoryLaunchArgument.
    static func usesInMemoryLibrary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool
```
Keep `isRunningUnitTests(environment:)` exactly as it is.

`AppLaunchModel.defaultFactory()` becomes:
```swift
nonisolated static func defaultFactory() throws -> AppEnvironment {
    if AppEnvironment.usesInMemoryLibrary() {
        return try AppEnvironment.inMemory()
    }
    return try AppEnvironment.live()
}
```
Don't change anything else in `AppLaunchModel`. T23 changes `start()` later.

## Tests (`AppEnvironmentTests`, struct name for the test filter: `AppEnvironmentTests`)
- `hostedProcessIsDetected`: call both functions with their **default arguments** (the real process environment). `#expect(AppEnvironment.isRunningUnitTests())` and `#expect(AppEnvironment.usesInMemoryLibrary())`. Add a doc comment: "If this fails, Xcode changed how it launches the test host. Fix detection before running any other test: the app would open the real library."
- `inMemoryLaunchArgumentIsHonoured`:
  - `usesInMemoryLibrary(environment: [:], arguments: ["StudyReader", "-StudyReaderInMemory"])` is true;
  - `usesInMemoryLibrary(environment: [:], arguments: ["StudyReader"])` is false;
  - `usesInMemoryLibrary(environment: ["XCTestBundlePath": "x"], arguments: [])` is true.
- `defaultFactoryUsesTemporaryLibraryInTests`: `let environment = try AppLaunchModel.defaultFactory()`, then `defer { TestFileStore.remove(environment.fileStore) }` (helper from T14). Expect:
  - `environment.fileStore.rootURL.path(percentEncoded: false).hasPrefix(FileManager.default.temporaryDirectory.path(percentEncoded: false))`;
  - `environment.fileStore != (try FileStore.applicationSupport())`. `FileStore` is `Equatable`, and `applicationSupport()` only builds a URL. It doesn't open the database.
- Keep the existing `detectsTestHost` unchanged.

Never call `AppEnvironment.live()` in a test.

## Acceptance criteria
1. The real test-host process is detected. → test `AppEnvironmentTests/hostedProcessIsDetected`
2. The launch argument forces in-memory mode, and its absence doesn't. → test `AppEnvironmentTests/inMemoryLaunchArgumentIsHonoured`
3. The default factory never picks the user's library inside tests. → test `AppEnvironmentTests/defaultFactoryUsesTemporaryLibraryInTests`
4. Existing tests still pass: `AppEnvironmentTests/detectsTestHost`, `AppLaunchModelTests`.
5. Mutation check, done by the reviewer by reading the code, not by running it: with a misspelled key in `isRunningUnitTests`, `hostedProcessIsDetected` would fail.
6. The full suite passes with no new warnings.

## Out of scope
- XCUITest targets. Only the argument is added.
- Async launch and error messages (T22, T23).
- Changing the environment variable names checked by `isRunningUnitTests`.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 100/100, spec match, mutation check by reading OK; minor note: no fixed-input assertion for XCTestConfigurationFilePath.
