import Foundation
import Testing

private actor CallCounter {
    private(set) var calls = 0

    func next() -> Int {
        calls += 1
        return calls
    }
}

@Suite("TestWait")
struct TestWaitTests {
    @Test(.timeLimit(.minutes(1)))
    func returnsTrueAsSoonAsTheConditionHolds() async {
        #expect(await TestWait.until { true })

        let counter = CallCounter()
        let reached = await TestWait.until { await counter.next() >= 4 }
        #expect(reached)
        #expect(await counter.calls == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func returnsFalseAfterTheTimeout() async {
        let clock = ContinuousClock()
        let start = clock.now
        let reached = await TestWait.until(timeout: .milliseconds(50)) { false }
        #expect(!reached)
        #expect(clock.now - start >= .milliseconds(50))
    }
}
