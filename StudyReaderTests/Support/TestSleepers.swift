import Foundation
import Testing
@testable import StudyReader

/// Returns at once.
struct ImmediateSleeper: Sleeper {
    func sleep(for duration: Duration) async throws {}
}

/// Each sleep suspends until `resumeAll()`. Records requested durations.
actor ManualSleeper: Sleeper {
    private(set) var requested: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int {
        continuations.count
    }

    func sleep(for duration: Duration) async throws {
        requested.append(duration)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let resumed = continuations
        continuations.removeAll()
        for continuation in resumed {
            continuation.resume()
        }
    }

    /// Polls up to 5 s (`TestWait`) until `n` sleeps are suspended; records an issue on timeout.
    func waitForSleepers(_ n: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        if await TestWait.until({ await self.pendingCount >= n }) { return }
        Issue.record(
            Comment(rawValue: "Timed out after 5 s waiting for \(n) sleepers; have \(pendingCount)"),
            sourceLocation: sourceLocation
        )
    }
}
