import Foundation

/// Waiting for time to pass. Logic waits only through an injected Sleeper (ADR-0015).
/// `SystemSleeper` is the only place that calls `Task.sleep`.
protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemSleeper: Sleeper {
    init() {}

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
