import Foundation

/// Time-bounded polling for tests (W1). Replaces "yield N times" loops, which give up too early on a loaded runner.
enum TestWait {
    static let timeout: Duration = .seconds(5)
    static let interval: Duration = .milliseconds(2)

    /// Calls `condition` until it returns true or `timeout` has passed on a `ContinuousClock`, sleeping `interval`
    /// between calls. Returns true as soon as the condition holds, false on timeout or when the task is cancelled.
    /// Callers must record an issue when it returns false, so a timeout always fails the test.
    static func until(
        timeout: Duration = TestWait.timeout,
        interval: Duration = TestWait.interval,
        _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if await condition() { return true }
            if clock.now >= deadline { return false }
            do {
                try await Task.sleep(for: interval)
            } catch {
                return false
            }
        }
    }
}
