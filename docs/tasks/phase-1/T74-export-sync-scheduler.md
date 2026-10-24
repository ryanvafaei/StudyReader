# T74: ExportSyncScheduler: keep in sync and retry when back online

- **Phase:** 1 (E1.8: F-21 "Keep in sync", offline queue)
- **Agent:** integrations
- **Depends on:** T73
- **ADRs:** docs/decisions/0018-google-export-seams-and-status.md, docs/decisions/0015-settings-and-injected-sleep.md (Sleeper, Debouncer), ARCHITECTURE §9.2 (keep-in-sync bullet)
- **Visual check needed:** no (covered by stubs; the user's T73 check already exercises export)

## Goal
While the app is open: for each target with "Keep in sync" on, re-export 60 s after the last relevant change; and re-run exports whose status is `queued` when the network comes back. Avoid needless uploads by skipping a sync whose rendered Markdown is unchanged since the last successful export in this app run.

## Files to touch
- `StudyReader/Features/Export/ExportSyncScheduler.swift` (new)
- `StudyReader/Features/Export/NetworkPathMonitoring.swift` (new: protocol + `NWPathMonitor` implementation)
- `StudyReader/Features/Export/GoogleExportService.swift` (modify: expose the rendered-content hash of the last successful export per target)
- `StudyReader/App/AppEnvironment.swift` (modify: `exportSyncScheduler`, plus `let runsExportSync: Bool` — an initializer parameter defaulting to `false`, set to `true` only by `live()`; `startBackgroundWork()` calls `exportSyncScheduler.start()` only when it is true)
- `StudyReaderTests/ExportTests/ExportSyncSchedulerTests.swift` (new), `StudyReaderTests/Support/StubNetworkPath.swift` (new)

## Interfaces to produce
```swift
protocol NetworkPathMonitoring: Sendable {
    /// Emits true when the path becomes satisfied, false when it becomes unsatisfied. First value = current state.
    func pathUpdates() -> AsyncStream<Bool>
}
struct SystemNetworkPathMonitor: NetworkPathMonitoring          // NWPathMonitor on its own DispatchQueue

/// What the scheduler needs from the export service (GoogleExportService conforms; tests stub it).
protocol ExportPerforming: Sendable {
    func export(targetId: String) async -> ExportOutcome
    /// SHA-256 of the Markdown that `export(targetId:)` would upload now (render only, no network).
    func renderedHash(targetId: String) async -> String?
    /// Hash recorded at the last successful export of this target in this app run, if any.
    func lastExportedHash(targetId: String) async -> String?
}

actor ExportSyncScheduler {
    static let syncDelay: Duration = .seconds(60)
    init(repository: ExportRepository, exporter: any ExportPerforming, network: any NetworkPathMonitoring,
         sleeper: any Sleeper)
    /// Starts two loops: (1) repository.observeChangeToken() → for every target with keepInSync, (re)schedule its
    /// per-target Debouncer(syncDelay); (2) network.pathUpdates() → on each transition to true, export every target
    /// whose lastStatus is "queued". Idempotent.
    func start()
    func stop()
    /// Debounced action for one target: skip when renderedHash == lastExportedHash; else exporter.export.
    func syncNow(targetId: String) async
}
```
- One `Debouncer` per target id (dictionary in the actor), created on first use.
- The first value of `observeChangeToken()` (initial state) doesn't schedule anything.
- Targets with `keepInSync` off are never exported by the scheduler, except `queued` ones on reconnect.
- Logging: target ids and outcomes only.

## Tests (`ExportSyncSchedulerTests`; in-memory environment; a recording `ExportPerforming` stub; `ManualSleeper`; `StubNetworkPath` with a controllable `AsyncStream`)
- `changeSchedulesSyncAfterDelay`: a keep-in-sync target; `start()`; change a highlight note → `waitForSleepers(1)`, requested duration 60 s; nothing exported yet; `resumeAll()` → exported once.
- `burstOfChangesExportsOnce`: three changes before resuming → one export.
- `keepInSyncOffIsIgnored`: change with keepInSync off → no sleeper, no export.
- `unchangedContentIsSkipped`: stub `renderedHash == lastExportedHash` → no export after the delay.
- `reconnectRetriesQueued`: target with `lastStatus "queued"` (keepInSync off) → network emits false then true → exported once.
- `stopCancels`: `stop()` before `resumeAll()` → no export.

## Acceptance criteria
1. Keep-in-sync exports 60 s after the last change, once per burst, only when content changed. → tests `changeSchedulesSyncAfterDelay`, `burstOfChangesExportsOnce`, `keepInSyncOffIsIgnored`, `unchangedContentIsSkipped`
2. Queued exports run when the network returns. → test `reconnectRetriesQueued` (SPEC F-21 errors: "offline: queue and retry when online")
3. The scheduler stops cleanly; it never runs in the test host's in-memory environment. → test `stopCancels` + code review (`startBackgroundWork` starts it only for `live()`)

## Out of scope
- Background sync while the app is closed (not in SPEC).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
