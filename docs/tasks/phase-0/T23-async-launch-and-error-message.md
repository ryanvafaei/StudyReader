# T23: Open the library off the main actor and show safe error messages

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L2, and L3 UI part)
- **Agent:** ui-builder
- **Depends on:** T15, T22
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md; ARCHITECTURE §3 (launch), §14 (errors)
- **Visual check needed:** yes

## Goal
`AppLaunchModel.start()` opens and migrates the library on the main actor, so the window freezes and the spinner doesn't animate during a slow open or migration. On failure it shows `error.localizedDescription`, which for a raw GRDB error can contain SQL. Make `start()` async with the factory running in a detached task. Show `AppDatabaseError`'s description and suggestion, and a generic message for any other error.

## Files to touch
- `StudyReader/App/AppLaunchModel.swift` (modify)
- `StudyReader/App/LaunchView.swift` (modify: `.task { await model.start() }`, failed-state preview)
- `StudyReaderTests/AppTests/AppLaunchModelTests.swift` (modify: rewrite as async)

## Interfaces to produce
```swift
@MainActor @Observable
final class AppLaunchModel {
    enum State { case loading, ready(AppEnvironment), failed(message: String) }   // unchanged
    private(set) var state: State = .loading
    private var hasStarted = false

    init(makeEnvironment: @escaping @Sendable () throws -> AppEnvironment = AppLaunchModel.defaultFactory)  // unchanged
    nonisolated static func defaultFactory() throws -> AppEnvironment   // unchanged (T15 version)

    /// Generic text for errors that aren't AppDatabaseError (never shows their description).
    /// `nonisolated` so the nonisolated failureMessage(for:) can read it.
    nonisolated static let genericFailureMessage = String(localized: "StudyReader couldn't open its library. Quit and reopen StudyReader.")

    /// AppDatabaseError → errorDescription, plus "\n\n" + recoverySuggestion when present.
    /// Any other error → genericFailureMessage.
    nonisolated static func failureMessage(for error: any Error) -> String

    /// Runs the factory once, in Task.detached(priority: .userInitiated), and awaits its Result.
    /// The second and later calls return immediately (hasStarted), even while the first is still running.
    /// Success → .ready. Failure → .failed(message: failureMessage(for:)), and logs
    /// Log.app.error("Library failed to open: \(String(describing: type(of: error)), privacy: .public)").
    func start() async
}
```
Implementation shape:
```swift
func start() async {
    guard !hasStarted else { return }
    hasStarted = true
    let factory = makeEnvironment
    let result = await Task.detached(priority: .userInitiated) {
        Result { try factory() }
    }.value
    switch result {
    case .success(let environment): state = .ready(environment)
    case .failure(let error):
        Log.app.error("Library failed to open: \(String(describing: type(of: error)), privacy: .public)")
        state = .failed(message: Self.failureMessage(for: error))
    }
}
```
No `@unchecked Sendable`, no `nonisolated(unsafe)`. `AppEnvironment` is `Sendable`, so `Result<AppEnvironment, any Error>` is too.

`LaunchView`:
- change `.task { model.start() }` to `.task { await model.start() }`;
- keep the three states and their texts;
- keep the existing `#Preview`, and add `#Preview("Failed")` with `LaunchView(model: AppLaunchModel(makeEnvironment: { throw AppDatabaseError.damaged(code: 26) }))`.

## Tests (`@Suite("AppLaunchModel") @MainActor struct AppLaunchModelTests`; filter `StudyReaderTests/AppLaunchModelTests`)
All tests are `async`. Environments are removed with `TestFileStore.remove(environment.fileStore)` (T14).
- `startBecomesReady`: factory `{ try AppEnvironment.inMemory() }`, then `await model.start()`, and the state is `.ready`. Remove the environment's folder.
- `startReportsFailureOnce`: factory increments a `Mutex<Int>` and throws `AppDatabaseError.migrationFailed(code: 1)`. `await model.start()` twice. Expect:
  - the state is `.failed(message:)` and the message equals `AppLaunchModel.failureMessage(for: AppDatabaseError.migrationFailed(code: 1))`;
  - that message starts with the case's `errorDescription` and ends with its `recoverySuggestion`;
  - the call count is 1.
- `concurrentStartsRunFactoryOnce`: factory increments the counter and returns `try AppEnvironment.inMemory()`. Run `async let first: Void = model.start()` and `async let second: Void = model.start()`, then `_ = await (first, second)`. The count is 1 and the state is `.ready`. Remove the folder.
- `factoryRunsOffMainThread`: the factory stores `Thread.isMainThread` in a `Mutex<Bool?>` and returns `try AppEnvironment.inMemory()`. After `await model.start()`, the stored value is `false`. Remove the folder.
- `unknownErrorsShowGenericMessage`: a factory throwing `DatabaseError(resultCode: .SQLITE_ERROR, message: "near \"CREATE\": syntax error", sql: "CREATE TABLE x (")` gives the message `AppLaunchModel.genericFailureMessage`, which doesn't contain `"CREATE"`. A second model, whose factory throws a `LocalizedError` with description `"Disk full"`, also gives `genericFailureMessage`.

`import GRDB` is needed in the test file for `DatabaseError`.

## Acceptance criteria
1. Start succeeds asynchronously. → test `AppLaunchModelTests/startBecomesReady`
2. Failures show the typed message and suggestion, and the factory runs once. → test `AppLaunchModelTests/startReportsFailureOnce`
3. Overlapping `start()` calls run the factory once. → test `AppLaunchModelTests/concurrentStartsRunFactoryOnce`
4. The factory doesn't run on the main thread. → test `AppLaunchModelTests/factoryRunsOffMainThread`
5. Raw database errors and other errors never reach the UI text. → test `AppLaunchModelTests/unknownErrorsShowGenericMessage`
6. Visual check (user):
   - Run the app (Debug). The spinner "Opening library…" may flash, then the main window with the sidebar appears as before.
   - In Xcode, open `LaunchView.swift` and select the "Failed" preview. It shows "Couldn't open the library", then "The library database is damaged." and the backup suggestion, with no SQL or codes.
7. The full suite passes with no new warnings.

## Out of scope
- Retry or reset buttons, and changes to the `State` enum's cases.
- Changing `defaultFactory` (T15) or `AppDatabaseError` (T22).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
