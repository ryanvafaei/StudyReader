import Foundation
import Testing
@testable import StudyReader

/// Records exports instead of uploading. Can hold exports until released, to test overlapping requests.
private actor RecordingExporter: ExportPerforming {
    private(set) var exported: [String] = []
    private(set) var hashRequests = 0
    private(set) var maxConcurrent = 0
    private var running = 0
    private var holds = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var outcome: ExportOutcome = .exported(fileId: "FILE1")
    /// Answers used first, one per export, before `outcome`.
    private var scripted: [ExportOutcome] = []
    private var rendered: String?
    private var last: String?

    var heldCount: Int {
        held.count
    }

    func configure(
        outcome: ExportOutcome? = nil,
        scripted: [ExportOutcome]? = nil,
        rendered: String?? = nil,
        last: String?? = nil,
        holds: Bool? = nil
    ) {
        if let outcome { self.outcome = outcome }
        if let scripted { self.scripted = scripted }
        if let rendered { self.rendered = rendered }
        if let last { self.last = last }
        if let holds { self.holds = holds }
    }

    func export(targetId: String) async -> ExportOutcome {
        running += 1
        maxConcurrent = max(maxConcurrent, running)
        exported.append(targetId)
        if holds {
            await withCheckedContinuation { held.append($0) }
        }
        running -= 1
        return scripted.isEmpty ? outcome : scripted.removeFirst()
    }

    func renderedHash(targetId: String) async -> String? {
        hashRequests += 1
        return rendered
    }

    func lastExportedHash(targetId: String) async -> String? {
        last
    }

    func releaseHeld() {
        let resumed = held
        held.removeAll()
        for continuation in resumed {
            continuation.resume()
        }
    }

    func waitForExports(_ n: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        if await TestWait.until({ await self.exported.count >= n }) { return }
        Issue.record(
            Comment(rawValue: "Timed out after 5 s waiting for \(n) exports; have \(exported.count): \(exported)"),
            sourceLocation: sourceLocation
        )
    }

    func waitForHeld(_ n: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        if await TestWait.until({ await self.heldCount >= n }) { return }
        Issue.record(
            Comment(rawValue: "Timed out after 5 s waiting for \(n) held exports; have \(held.count)"),
            sourceLocation: sourceLocation
        )
    }

    func waitForHashRequests(_ n: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        if await TestWait.until({ await self.hashRequests >= n }) { return }
        Issue.record(
            Comment(rawValue: "Timed out after 5 s waiting for \(n) hash requests; have \(hashRequests)"),
            sourceLocation: sourceLocation
        )
    }
}

@Suite("ExportSyncScheduler")
struct ExportSyncSchedulerTests {
    private static let docId = "10000000-0000-0000-0000-0000000000B1"
    private static let highlightId = "20000000-0000-0000-0000-0000000000B1"

    private struct Harness {
        let repository: ExportRepository
        let highlights: HighlightRepository
        let exporter = RecordingExporter()
        let network = StubNetworkPath()
        let sleeper = ManualSleeper()
        let scheduler: ExportSyncScheduler

        init(targets: [ExportTarget]) async throws {
            let database = try AppDatabase.makeInMemory()
            try await DocumentRepository(database: database).insert(TestData.document(id: ExportSyncSchedulerTests.docId))
            let highlights = HighlightRepository(database: database)
            try await highlights.insert(
                TestData.highlight(documentId: ExportSyncSchedulerTests.docId, id: ExportSyncSchedulerTests.highlightId)
            )
            let repository = ExportRepository(database: database)
            for target in targets {
                try await repository.insertTarget(target)
            }
            self.repository = repository
            self.highlights = highlights
            self.scheduler = ExportSyncScheduler(
                repository: repository,
                exporter: exporter,
                network: network,
                sleeper: sleeper
            )
        }

        /// Starts the scheduler and waits until it has read the current database state, so later edits count.
        func start(sourceLocation: SourceLocation = #_sourceLocation) async {
            let scheduler = scheduler
            await scheduler.start()
            if await TestWait.until({ await scheduler.isWatchingChanges }) { return }
            Issue.record(
                Comment(rawValue: "Timed out after 5 s: the scheduler never read the initial state"),
                sourceLocation: sourceLocation
            )
        }

        /// A highlight note of a new length: changes what an export reads.
        func edit(_ length: Int) async throws {
            try await highlights.updateNote(
                id: ExportSyncSchedulerTests.highlightId,
                note: String(repeating: "n", count: length),
                at: TestData.referenceDate.addingTimeInterval(Double(length))
            )
        }
    }

    private static func target(id: String, keepInSync: Bool = false, status: ExportStatus = .never) -> ExportTarget {
        var target = TestData.exportTarget(id: id)
        target.keepInSync = keepInSync
        target.lastStatus = status.rawValue
        return target
    }

    @Test(.timeLimit(.minutes(1)))
    func changeSchedulesSyncAfterDelay() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.start()

        try await h.edit(1)
        await h.sleeper.waitForSleepers(1)
        #expect(await h.sleeper.requested == [.seconds(60)])
        #expect(await h.exporter.exported.isEmpty)

        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(1)
        #expect(await h.exporter.exported == ["T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func burstOfChangesExportsOnce() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.start()

        for length in 1...3 {
            try await h.edit(length)
            await h.sleeper.waitForSleepers(length)
        }
        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await h.exporter.exported == ["T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func keepInSyncOffIsIgnored() async throws {
        let h = try await Harness(targets: [
            Self.target(id: "Off", keepInSync: false),
            Self.target(id: "On", keepInSync: true),
        ])
        await h.start()

        try await h.edit(1)
        await h.sleeper.waitForSleepers(1)
        #expect(await h.sleeper.requested.count == 1)
        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await h.exporter.exported == ["On"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func unchangedContentIsSkipped() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.exporter.configure(rendered: "hash-a", last: "hash-a")
        await h.start()

        try await h.edit(1)
        await h.sleeper.waitForSleepers(1)
        await h.sleeper.resumeAll()
        await h.exporter.waitForHashRequests(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await h.exporter.exported.isEmpty)

        await h.exporter.configure(rendered: "hash-b")
        try await h.edit(2)
        await h.sleeper.waitForSleepers(1)
        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(1)
        #expect(await h.exporter.exported == ["T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func reconnectRetriesQueued() async throws {
        let h = try await Harness(targets: [
            Self.target(id: "Queued", status: .queued),
            Self.target(id: "Done", status: .ok),
        ])
        await h.start()

        h.network.emit(false)
        h.network.emit(true)
        await h.exporter.waitForExports(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await h.exporter.exported == ["Queued"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func queuedIsRetriedWhenOnlineAtLaunch() async throws {
        let h = try await Harness(targets: [Self.target(id: "Queued", status: .queued)])
        await h.start()

        h.network.emit(true)
        await h.exporter.waitForExports(1)
        #expect(await h.exporter.exported == ["Queued"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func stopCancels() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.start()

        try await h.edit(1)
        await h.sleeper.waitForSleepers(1)
        await h.scheduler.stop()
        await h.sleeper.resumeAll()
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.exporter.exported.isEmpty)
        #expect(await h.scheduler.isRunning == false)

        try await h.edit(2)
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.sleeper.pendingCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func overlappingRequestsRunOneAfterAnother() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.exporter.configure(holds: true)
        await h.start()

        let first = Task { await h.scheduler.syncNow(targetId: "T1") }
        await h.exporter.waitForHeld(1)
        await h.scheduler.syncNow(targetId: "T1")
        await h.scheduler.syncNow(targetId: "T1")
        #expect(await h.exporter.exported == ["T1"])

        await h.exporter.configure(holds: false)
        await h.exporter.releaseHeld()
        await first.value
        #expect(await h.exporter.exported == ["T1", "T1"])
        #expect(await h.exporter.maxConcurrent == 1)
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func failuresRetryAFewTimesOnly() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.exporter.configure(outcome: .failed("Couldn't reach Google Drive."))
        await h.start()

        try await h.edit(1)
        for round in 1...(1 + ExportSyncScheduler.maxFailureRetries) {
            await h.sleeper.waitForSleepers(1)
            await h.sleeper.resumeAll()
            await h.exporter.waitForExports(round)
        }
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.exporter.exported.count == 1 + ExportSyncScheduler.maxFailureRetries)
        #expect(await h.sleeper.pendingCount == 0)
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func successResetsFailureRetries() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        let failed = ExportOutcome.failed("Couldn't reach Google Drive.")
        await h.exporter.configure(
            outcome: failed,
            scripted: [failed, failed, .exported(fileId: "FILE1")]
        )
        await h.start()

        try await h.edit(1)
        for round in 1...3 {
            await h.sleeper.waitForSleepers(1)
            await h.sleeper.resumeAll()
            await h.exporter.waitForExports(round)
        }
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.sleeper.pendingCount == 0)

        await h.scheduler.syncNow(targetId: "T1")
        let retries = ExportSyncScheduler.maxFailureRetries
        for round in 5...(4 + retries) {
            await h.sleeper.waitForSleepers(1)
            await h.sleeper.resumeAll()
            await h.exporter.waitForExports(round)
        }
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.exporter.exported.count == 4 + retries)
        #expect(await h.sleeper.pendingCount == 0)
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func queuedWhileOnlineRetriesAfterDelay() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", status: .queued)])
        await h.exporter.configure(scripted: [.queued, .exported(fileId: "FILE1")])
        await h.start()

        h.network.emit(true)
        await h.exporter.waitForExports(1)
        await h.sleeper.waitForSleepers(1)
        #expect(await h.sleeper.requested == [ExportSyncScheduler.syncDelay])
        #expect(await h.exporter.exported == ["T1"])

        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(2)
        #expect(await h.exporter.exported == ["T1", "T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func queuedWhileOfflineWaitsForTheNetwork() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.exporter.configure(outcome: .queued)
        await h.start()

        try await h.edit(1)
        await h.sleeper.waitForSleepers(1)
        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(1)
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.sleeper.pendingCount == 0)
        #expect(await h.exporter.exported == ["T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledExportIsNotRetried() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.exporter.configure(outcome: .cancelled)
        await h.start()

        try await h.edit(1)
        await h.sleeper.waitForSleepers(1)
        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(1)
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.sleeper.pendingCount == 0)
        #expect(await h.exporter.exported == ["T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func queuedTargetsRetryInParallel() async throws {
        let h = try await Harness(targets: [
            Self.target(id: "A", status: .queued),
            Self.target(id: "B", status: .queued),
        ])
        await h.exporter.configure(holds: true)
        await h.start()

        h.network.emit(true)
        await h.exporter.waitForHeld(2)
        #expect(await h.exporter.heldCount == 2)
        #expect(await h.exporter.maxConcurrent == 2)

        await h.exporter.configure(holds: false)
        await h.exporter.releaseHeld()
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func stopWhileInFlightRunsNothingAfter() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: true)])
        await h.exporter.configure(outcome: .failed("Couldn't reach Google Drive."), holds: true)
        await h.start()

        let first = Task { await h.scheduler.syncNow(targetId: "T1") }
        await h.exporter.waitForHeld(1)
        await h.scheduler.syncNow(targetId: "T1")
        await h.scheduler.stop()

        await h.exporter.configure(holds: false)
        await h.exporter.releaseHeld()
        await first.value
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.exporter.exported == ["T1"])
        #expect(await h.sleeper.pendingCount == 0)
    }

    // MARK: Manual exports (T94, M2 b)

    @Test(.timeLimit(.minutes(1)))
    func manualQueuedExportRetriesWhileOnline() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: false, status: .queued)])
        await h.start()

        h.network.emit(true)
        await h.exporter.waitForExports(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await h.sleeper.pendingCount == 0)

        await h.scheduler.manualExportEnded(targetId: "T1", outcome: .queued)
        await h.sleeper.waitForSleepers(1)
        #expect(await h.sleeper.requested == [ExportSyncScheduler.syncDelay])
        #expect(await h.exporter.exported == ["T1"])

        await h.sleeper.resumeAll()
        await h.exporter.waitForExports(2)
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.exporter.exported == ["T1", "T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func manualQueuedExportWaitsForTheNetworkWhenOffline() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: false, status: .queued)])
        await h.start()

        await h.scheduler.manualExportEnded(targetId: "T1", outcome: .queued)
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.sleeper.pendingCount == 0)
        #expect(await h.sleeper.requested.isEmpty)
        #expect(await h.exporter.exported.isEmpty)

        h.network.emit(true)
        await h.exporter.waitForExports(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await h.exporter.exported == ["T1"])
        await h.scheduler.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func manualExportEndedIgnoresOtherOutcomes() async throws {
        let h = try await Harness(targets: [Self.target(id: "T1", keepInSync: false, status: .ok)])
        let outcomes: [ExportOutcome] = [
            .exported(fileId: "FILE1"), .failed("Couldn't reach Google Drive."), .docMissing,
            .signInRequired, .cancelled, .notConfigured,
        ]

        await h.scheduler.manualExportEnded(targetId: "T1", outcome: .queued)
        #expect(await h.sleeper.requested.isEmpty)

        await h.start()
        h.network.emit(true)
        for _ in 0..<200 {
            await Task.yield()
        }
        for outcome in outcomes {
            await h.scheduler.manualExportEnded(targetId: "T1", outcome: outcome)
        }
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await h.sleeper.requested.isEmpty)
        #expect(await h.exporter.exported.isEmpty)

        await h.scheduler.manualExportEnded(targetId: "T1", outcome: .queued)
        await h.sleeper.waitForSleepers(1)
        #expect(await h.sleeper.requested == [ExportSyncScheduler.syncDelay])
        await h.scheduler.stop()
    }
}
