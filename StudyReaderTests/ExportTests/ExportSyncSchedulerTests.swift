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
    private var rendered: String?
    private var last: String?

    var heldCount: Int {
        held.count
    }

    func configure(outcome: ExportOutcome? = nil, rendered: String?? = nil, last: String?? = nil, holds: Bool? = nil) {
        if let outcome { self.outcome = outcome }
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
        return outcome
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

    func waitForExports(_ n: Int) async {
        for _ in 0..<10_000 {
            if exported.count >= n { return }
            await Task.yield()
        }
        Issue.record("Expected \(n) exports, have \(exported.count)")
    }

    func waitForHeld(_ n: Int) async {
        for _ in 0..<10_000 {
            if held.count >= n { return }
            await Task.yield()
        }
        Issue.record("Expected \(n) held exports, have \(held.count)")
    }

    func waitForHashRequests(_ n: Int) async {
        for _ in 0..<10_000 {
            if hashRequests >= n { return }
            await Task.yield()
        }
        Issue.record("Expected \(n) hash requests, have \(hashRequests)")
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
        func start() async {
            await scheduler.start()
            for _ in 0..<10_000 {
                if await scheduler.isWatchingChanges { return }
                await Task.yield()
            }
            Issue.record("The scheduler never read the initial state")
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
}
