import Foundation
import Testing
@testable import StudyReader

/// Collects values written by debounced actions.
actor ValueRecorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}

@Suite struct DebouncerTests {
    @Test func runsOnlyLastAction() async {
        let sleeper = ManualSleeper()
        let debouncer = Debouncer(delay: .milliseconds(500), sleeper: sleeper)
        let recorder = ValueRecorder()

        for value in 1...3 {
            await debouncer.schedule { await recorder.append(value) }
        }
        await sleeper.waitForSleepers(3)
        await sleeper.resumeAll()

        for _ in 0..<10_000 {
            if await !recorder.values.isEmpty { break }
            await Task.yield()
        }
        let values = await recorder.values
        let requested = await sleeper.requested
        #expect(values == [3])
        #expect(requested == Array(repeating: Duration.milliseconds(500), count: 3))
    }

    @Test func flushRunsPendingNow() async {
        let sleeper = ManualSleeper()
        let debouncer = Debouncer(delay: .milliseconds(500), sleeper: sleeper)
        let recorder = ValueRecorder()

        await debouncer.schedule { await recorder.append(1) }
        await sleeper.waitForSleepers(1)
        await debouncer.flush()

        let afterFlush = await recorder.values
        #expect(afterFlush == [1])

        await sleeper.resumeAll()
        for _ in 0..<100 {
            await Task.yield()
        }
        let afterResume = await recorder.values
        #expect(afterResume == [1])
        let hasPending = await debouncer.hasPendingAction
        #expect(hasPending == false)
    }

    @Test func cancelDropsAction() async {
        let sleeper = ManualSleeper()
        let debouncer = Debouncer(delay: .milliseconds(500), sleeper: sleeper)
        let recorder = ValueRecorder()

        await debouncer.schedule { await recorder.append(1) }
        await sleeper.waitForSleepers(1)
        await debouncer.cancel()
        let hasPending = await debouncer.hasPendingAction
        #expect(hasPending == false)

        await sleeper.resumeAll()
        for _ in 0..<100 {
            await Task.yield()
        }
        await debouncer.flush()
        let values = await recorder.values
        #expect(values.isEmpty)
    }
}
