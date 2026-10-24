# T33: Core support: Hashing, Sleeper, Debouncer, SettingsStore

- **Phase:** 1 (E1.1 groundwork)
- **Agent:** data-layer
- **Depends on:** T29
- **ADRs:** docs/decisions/0015-settings-and-injected-sleep.md (read it in full), ARCHITECTURE §3 (injection)
- **Visual check needed:** no

## Goal
Shared building blocks that many Phase 1 tasks use: file hashing for import dedupe (F-02), an injectable sleep for debouncing and backoff, a debouncer for autosave, and a typed settings store. Wire `SettingsStore` and `Sleeper` into `AppEnvironment`.

## Files to touch
- `StudyReader/Core/Support/Hashing.swift` (new)
- `StudyReader/Core/Support/Sleeper.swift` (new)
- `StudyReader/Core/Support/Debounce.swift` (new)
- `StudyReader/Core/Support/SettingsStore.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify)
- `StudyReaderTests/Support/TestSleepers.swift` (new), `StudyReaderTests/Support/TestSettings.swift` (new)
- `StudyReaderTests/CoreTests/HashingTests.swift`, `DebouncerTests.swift`, `SettingsStoreTests.swift` (new)

## Interfaces to produce
```swift
import CryptoKit
enum Hashing {
    /// Lowercase hex SHA-256 (64 chars) of the file's bytes, read with FileHandle in 1 MiB chunks.
    static func sha256Hex(ofFileAt url: URL) throws -> String
    /// Lowercase hex SHA-256 of `data`.
    static func sha256Hex(of data: Data) -> String
    /// Lowercase hex SHA-256 of `string.utf8`.
    static func sha256Hex(of string: String) -> String
}

protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}
struct SystemSleeper: Sleeper {
    init() {}
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

/// Runs only the most recently scheduled action, `delay` after it was scheduled (ADR-0015).
actor Debouncer {
    init(delay: Duration, sleeper: any Sleeper)
    /// Replaces any pending action. Starts a Task: sleep(delay); if no newer schedule/cancel/flush happened
    /// (generation counter unchanged), run the action.
    func schedule(_ action: @escaping @Sendable () async -> Void)
    /// Runs the pending action now (if any) and awaits it; the sleeping task then does nothing.
    func flush() async
    /// Drops the pending action.
    func cancel()
    var hasPendingAction: Bool { get }
}

enum LibraryLayout: String, Sendable, CaseIterable { case grid, list }
enum LibrarySort: String, Sendable, CaseIterable { case dateAdded, lastOpened, title, author }

/// Typed per-Mac preferences over one UserDefaults (ADR-0015). Keys are "settings.<property>".
struct SettingsStore: Sendable {
    let defaults: UserDefaults
    init(defaults: UserDefaults)
    static func standard() -> SettingsStore                       // UserDefaults.standard
    static let ephemeralSuiteName = "com.ryanvafaei.StudyReader.Ephemeral"
    static func ephemeral() -> SettingsStore                      // UserDefaults(suiteName: ephemeralSuiteName)!

    var defaultCategoryId: String { get nonmutating set }         // default BuiltinCategory.lectureSlides.id
    var autoHighlight: Bool { get nonmutating set }               // default true
    var currentColor: HighlightColor { get nonmutating set }      // default .yellow (stored as Int raw value)
    var invertPDFInDarkMode: Bool { get nonmutating set }         // default true
    var googleExportFolderId: String? { get nonmutating set }     // default nil; setting nil removes the key
    var libraryLayout: LibraryLayout { get nonmutating set }      // default .grid
    var librarySort: LibrarySort { get nonmutating set }          // default .dateAdded
    func colorLabel(for color: HighlightColor) -> String          // stored label, or the default below
    func setColorLabel(_ label: String, for color: HighlightColor) // trimmed; empty → removes the key (back to default)
    static func defaultColorLabel(for color: HighlightColor) -> String
    // yellow "Key concept", green "Exam", blue "Connection", pink "Question", purple "Don't understand"
}
```
- Keys: `settings.defaultCategoryId`, `settings.autoHighlight`, `settings.currentColor`, `settings.invertPDFInDarkMode`, `settings.googleExportFolderId`, `settings.libraryLayout`, `settings.librarySort`, `settings.colorLabel.<rawValue>` (0–4). Bool getters return the default when the key is absent (use `object(forKey:) as? Bool`), not `false`. Unknown raw values fall back to the default.
- If the compiler reports `UserDefaults` isn't `Sendable`, store `suiteName: String?` instead and resolve `UserDefaults(suiteName:) ?? .standard` per access; say so in your report.

`AppEnvironment` changes:
- New stored properties `let settingsStore: SettingsStore` and `let sleeper: any Sleeper`.
- `init(fileStore:database:now:settingsStore: SettingsStore = .ephemeral(), sleeper: any Sleeper = SystemSleeper())`; existing call sites keep compiling.
- `live()` passes `.standard()` (through `make(fileStore:now:settingsStore:)`, add the parameter with default `.ephemeral()`); `inMemory(now:)` passes `.ephemeral()`.

Test support:
```swift
struct ImmediateSleeper: Sleeper {            // returns at once; records nothing
    func sleep(for duration: Duration) async throws {}
}
/// Each sleep suspends until resumeAll(). Records requested durations.
actor ManualSleeper: Sleeper {
    private(set) var requested: [Duration]
    var pendingCount: Int { get }
    func sleep(for duration: Duration) async throws    // append duration; await withCheckedContinuation, stored in a list
    func resumeAll()                                    // resumes and clears every stored continuation
    /// Polls (await Task.yield()) until pendingCount >= n; gives up after 10_000 yields with Issue.record.
    func waitForSleepers(_ n: Int) async
}
enum TestSettings {
    /// SettingsStore over UserDefaults(suiteName: "StudyReaderTests-<UUID>").
    static func make() -> SettingsStore
    /// removePersistentDomain(forName:) for that suite.
    static func remove(_ store: SettingsStore)
}
```
`TestSettings.remove` needs the suite name: keep it in `SettingsStore` as `let suiteName: String?` (nil for `.standard()`), set by an extra initializer `init(suiteName: String)`.

## Tests
- `HashingTests/knownVectors`: `sha256Hex(of: "abc")` == `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`; empty data == `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- `HashingTests/fileMatchesData`: write 3 MiB + 17 bytes of patterned data to a temp file; `sha256Hex(ofFileAt:) == sha256Hex(of: data)`. Remove the file in `defer`.
- `HashingTests/missingFileThrows`.
- `DebouncerTests/runsOnlyLastAction`: `ManualSleeper`, delay `.milliseconds(500)`; schedule three actions that append 1, 2, 3 to an actor-held array; `await sleeper.waitForSleepers(3)`; `await sleeper.resumeAll()`; then poll until the array is non-empty (bounded); array == `[3]`; `requested == Array(repeating: .milliseconds(500), count: 3)`.
- `DebouncerTests/flushRunsPendingNow`: schedule one action; `await flush()`; action ran once; then `resumeAll()` and yield; still once; `hasPendingAction == false`.
- `DebouncerTests/cancelDropsAction`.
- `SettingsStoreTests/defaults`: fresh `TestSettings.make()` returns every default listed above (+ `remove` in `defer`).
- `SettingsStoreTests/roundTrips`: set every property to a non-default value; a second `SettingsStore(defaults:)` over the same `UserDefaults` reads them back. `googleExportFolderId = nil` removes the key.
- `SettingsStoreTests/colorLabels`: default labels for all five colors; `setColorLabel("  Exam prep ", for: .green)` → `"Exam prep"`; `setColorLabel("", for: .green)` → back to `"Exam"`.
- `SettingsStoreTests/environmentUsesEphemeralSuiteInMemory`: `AppEnvironment.inMemory().settingsStore.suiteName == SettingsStore.ephemeralSuiteName` (remove the env folder with `TestFileStore.remove`).

## Acceptance criteria
1. SHA-256 matches known vectors, streaming equals in-memory. → tests `HashingTests/*`
2. The debouncer runs only the last action, `flush` runs it now, `cancel` drops it. → tests `DebouncerTests/*`
3. Settings have the listed defaults and persist. → tests `SettingsStoreTests/*`
4. Tests and the test host never use `UserDefaults.standard` (only `live()` does). → code review + `SettingsStoreTests/environmentUsesEphemeralSuiteInMemory`
5. Full suite passes; no call to `Task.sleep` outside `SystemSleeper`.

## Out of scope
- `AppSettings`/`AppSession` (T45) and any UI.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. suiteName fallback allowed by spec; 181 tests pass.
