import Foundation

/// What the scheduler needs from the export service (`GoogleExportService` conforms; tests stub it).
protocol ExportPerforming: Sendable {
    func export(targetId: String) async -> ExportOutcome
    /// SHA-256 of the Markdown that `export(targetId:)` would upload now (render only, no network).
    func renderedHash(targetId: String) async -> String?
    /// Hash recorded at the last successful export of this target in this app run, if any.
    func lastExportedHash(targetId: String) async -> String?
}

extension GoogleExportService: ExportPerforming {}

/// Keep in sync and retry when back online (SPEC F-21, ARCHITECTURE §9.2, ADR-0015, ADR-0018).
///
/// - A change to anything an export reads schedules, for every target with "Keep in sync" on, one export
///   `syncDelay` after the last change. The export is skipped when the Markdown is the one the last successful
///   export of this app run uploaded.
/// - When the network path becomes satisfied, every target whose status is `queued` is exported again.
/// - Exports of one target never overlap: a request that arrives while one runs is remembered and runs once, after it.
/// - A failed export is retried up to `maxFailureRetries` times, `syncDelay` apart; a new change starts the count over.
///   Offline results wait for the network instead; sign-in and missing-Doc results wait for the user.
///
/// Logs target ids and outcome names only.
actor ExportSyncScheduler {
    static let syncDelay: Duration = .seconds(60)
    static let maxFailureRetries = 3

    private static let log = Log.logger("export")

    private let repository: ExportRepository
    private let exporter: any ExportPerforming
    private let network: any NetworkPathMonitoring
    private let sleeper: any Sleeper

    private var debouncers: [String: Debouncer] = [:]
    private var changeTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    /// Targets with an export running, and those that asked for another one meanwhile.
    private var inFlight: Set<String> = []
    private var followUp: Set<String> = []
    private var failureRetries: [String: Int] = [:]

    /// true once the current state of the database has been read, so later changes count. Reset by `stop()`.
    private(set) var isWatchingChanges = false

    init(
        repository: ExportRepository,
        exporter: any ExportPerforming,
        network: any NetworkPathMonitoring,
        sleeper: any Sleeper
    ) {
        self.repository = repository
        self.exporter = exporter
        self.network = network
        self.sleeper = sleeper
    }

    var isRunning: Bool {
        changeTask != nil
    }

    // MARK: Lifecycle

    /// Starts watching database changes and the network path. Does nothing when already started.
    func start() {
        guard changeTask == nil else { return }
        changeTask = Task { await self.watchChanges() }
        networkTask = Task { await self.watchNetwork() }
    }

    /// Stops both loops and drops every scheduled export. An export already running finishes; nothing follows it.
    func stop() async {
        changeTask?.cancel()
        networkTask?.cancel()
        changeTask = nil
        networkTask = nil
        isWatchingChanges = false
        followUp.removeAll()
        failureRetries.removeAll()
        let scheduled = Array(debouncers.values)
        debouncers.removeAll()
        for debouncer in scheduled {
            await debouncer.cancel()
        }
    }

    // MARK: Sync

    /// The debounced action for one target. Exports when the target keeps in sync and its Markdown differs from the
    /// last successful export, or when its status is `queued`. Never overlaps another export of the same target.
    func syncNow(targetId: String) async {
        guard inFlight.insert(targetId).inserted else {
            followUp.insert(targetId)
            return
        }
        defer { inFlight.remove(targetId) }
        while true {
            if let outcome = await exportIfNeeded(targetId: targetId) {
                Self.log.info("Sync of \(targetId, privacy: .public): \(Self.name(of: outcome), privacy: .public)")
                await scheduleRetryIfFailed(outcome, targetId: targetId)
            }
            guard isRunning, followUp.remove(targetId) != nil else { break }
        }
    }

    private func exportIfNeeded(targetId: String) async -> ExportOutcome? {
        guard let target = try? await repository.fetchTarget(id: targetId) else { return nil }
        if target.lastStatus != ExportStatus.queued.rawValue {
            guard target.keepInSync else { return nil }
            let rendered = await exporter.renderedHash(targetId: targetId)
            let last = await exporter.lastExportedHash(targetId: targetId)
            if let rendered, rendered == last {
                Self.log.info("Sync of \(targetId, privacy: .public) skipped: unchanged")
                return nil
            }
        }
        return await exporter.export(targetId: targetId)
    }

    private func scheduleRetryIfFailed(_ outcome: ExportOutcome, targetId: String) async {
        guard case .failed = outcome, isRunning else { return }
        let attempts = failureRetries[targetId, default: 0]
        guard attempts < Self.maxFailureRetries else { return }
        failureRetries[targetId] = attempts + 1
        await schedule(targetId: targetId)
    }

    private func schedule(targetId: String) async {
        let debouncer: Debouncer
        if let existing = debouncers[targetId] {
            debouncer = existing
        } else {
            debouncer = Debouncer(delay: Self.syncDelay, sleeper: sleeper)
            debouncers[targetId] = debouncer
        }
        await debouncer.schedule { [self] in
            guard await isRunning else { return }
            await syncNow(targetId: targetId)
        }
    }

    // MARK: Loops

    private func watchChanges() async {
        var previous: Int?
        do {
            for try await token in repository.observeChangeToken() {
                if Task.isCancelled { return }
                guard let last = previous else {
                    previous = token
                    isWatchingChanges = true
                    continue
                }
                guard token != last else { continue }
                previous = token
                await changed()
            }
        } catch {
            Self.log.error("Watching export changes stopped")
        }
    }

    private func changed() async {
        let targets = (try? await repository.fetchTargets()) ?? []
        for target in targets where target.keepInSync {
            guard isRunning else { return }
            failureRetries[target.id] = nil
            await schedule(targetId: target.id)
        }
    }

    private func watchNetwork() async {
        var wasSatisfied = false
        for await satisfied in network.pathUpdates() {
            if Task.isCancelled { return }
            let becameSatisfied = satisfied && !wasSatisfied
            wasSatisfied = satisfied
            if becameSatisfied {
                await retryQueued()
            }
        }
    }

    private func retryQueued() async {
        let targets = (try? await repository.fetchTargets()) ?? []
        for target in targets where target.lastStatus == ExportStatus.queued.rawValue {
            guard isRunning else { return }
            await syncNow(targetId: target.id)
        }
    }

    private static func name(of outcome: ExportOutcome) -> String {
        switch outcome {
        case .exported: "exported"
        case .queued: "queued"
        case .signInRequired: "signInRequired"
        case .docMissing: "docMissing"
        case .notConfigured: "notConfigured"
        case .failed: "failed"
        }
    }
}
