import Foundation

/// Runs only the most recently scheduled action, `delay` after it was scheduled (ADR-0015).
actor Debouncer {
    private let delay: Duration
    private let sleeper: any Sleeper
    private var pendingAction: (@Sendable () async -> Void)?
    /// Bumped by every schedule, flush and cancel. A sleeping task runs its action only if this is unchanged.
    private var generation = 0

    init(delay: Duration, sleeper: any Sleeper) {
        self.delay = delay
        self.sleeper = sleeper
    }

    var hasPendingAction: Bool {
        pendingAction != nil
    }

    /// Replaces any pending action and starts a task that waits `delay` before running it.
    func schedule(_ action: @escaping @Sendable () async -> Void) {
        generation += 1
        let scheduled = generation
        pendingAction = action
        Task {
            await self.runIfCurrent(scheduled: scheduled)
        }
    }

    /// Runs the pending action now and awaits it. The sleeping task then does nothing.
    func flush() async {
        generation += 1
        guard let action = pendingAction else { return }
        pendingAction = nil
        await action()
    }

    /// Drops the pending action.
    func cancel() {
        generation += 1
        pendingAction = nil
    }

    private func runIfCurrent(scheduled: Int) async {
        do {
            try await sleeper.sleep(for: delay)
        } catch {
            return
        }
        guard scheduled == generation, let action = pendingAction else { return }
        pendingAction = nil
        await action()
    }
}
