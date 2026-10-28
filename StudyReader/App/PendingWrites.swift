import Foundation

/// Something with debounced writes that must land before the app quits.
@MainActor
protocol PendingWriteFlushing: AnyObject {
    /// Saves anything still waiting for its debounce, and returns when the write has finished (or failed).
    func flushPendingWrites() async
}

/// Weak registry of live writers (NoteEditorModel, ReaderModel). Owned by `AppEnvironment`; one per library.
/// Quit flushes every live writer before the app terminates (`AppDelegate.applicationShouldTerminate`).
@MainActor
final class PendingWrites {
    private struct WeakWriter {
        weak var value: (any PendingWriteFlushing)?
    }

    private var writers: [WeakWriter] = []

    /// `AppEnvironment` is built off the main actor.
    nonisolated init() {}

    /// Adds `writer` weakly. Registering the same object twice keeps one entry.
    func register(_ writer: any PendingWriteFlushing) {
        prune()
        guard !writers.contains(where: { $0.value === writer }) else { return }
        writers.append(WeakWriter(value: writer))
    }

    /// Number of live (not yet deallocated) writers. Prunes dead entries.
    var liveCount: Int {
        prune()
        return writers.count
    }

    /// Calls `flushPendingWrites()` on every live writer, one after another, and returns when all have finished.
    /// Writers registered or deallocated meanwhile are fine (a snapshot of the live ones is flushed).
    func flushAll() async {
        prune()
        let snapshot = writers.compactMap(\.value)
        for writer in snapshot {
            await writer.flushPendingWrites()
        }
    }

    private func prune() {
        writers.removeAll { $0.value == nil }
    }
}

extension AppDelegate {
    /// Set by `AppLaunchModel.start()` when the library opens; nil before (quit then terminates at once).
    @MainActor static var terminationWrites: PendingWrites?
}
