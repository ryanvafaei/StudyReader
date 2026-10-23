import Foundation
import Testing
@testable import StudyReader

@Suite struct NowTests {
    @Test func fixedNowSetAndAdvance() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = FixedNow(start)
        #expect(clock() == start)

        clock.advance(by: 90)
        #expect(clock() == start.addingTimeInterval(90))

        let other = Date(timeIntervalSince1970: 1_700_000_000)
        clock.set(other)
        #expect(clock() == other)
    }

    @Test func systemNowIsCurrent() {
        let before = Date()
        let now = SystemNow()()
        let after = Date()
        #expect(now >= before.addingTimeInterval(-5))
        #expect(now <= after.addingTimeInterval(5))
    }
}
