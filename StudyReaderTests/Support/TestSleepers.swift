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

    /// Yields until `n` sleeps are suspended. Gives up after 10_000 yields with an issue.
    func waitForSleepers(_ n: Int) async {
        for _ in 0..<10_000 {
            if pendingCount >= n { return }
            await Task.yield()
        }
        Issue.record("Expected \(n) sleepers, have \(pendingCount)")
    }
}
