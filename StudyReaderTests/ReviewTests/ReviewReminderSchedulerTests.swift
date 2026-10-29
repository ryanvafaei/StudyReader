import Testing
@testable import StudyReader

@MainActor
struct ReviewReminderSchedulerTests {
    private let id = ReviewReminderScheduler.identifier

    @Test func enablingSchedulesDaily() async {
        let center = StubNotificationCenter()
        let scheduler = ReviewReminderScheduler(center: center)
        let result = await scheduler.apply(enabled: true, minutes: 545)
        #expect(result)
        #expect(center.calls == [
            .requestAuthorization,
            .removePending(id),
            .scheduleDaily(identifier: id, hour: 9, minute: 5)
        ])
        #expect(scheduler.deniedMessage == nil)
    }

    @Test func disablingRemoves() async {
        let center = StubNotificationCenter()
        let scheduler = ReviewReminderScheduler(center: center)
        await scheduler.apply(enabled: false, minutes: 545)
        #expect(center.calls == [.removePending(id)])
    }

    @Test func deniedTurnsOffAndExplains() async {
        let center = StubNotificationCenter(grants: false)
        let scheduler = ReviewReminderScheduler(center: center)
        let result = await scheduler.apply(enabled: true, minutes: 545)
        #expect(!result)
        #expect(scheduler.deniedMessage != nil)
        #expect(!center.calls.contains { if case .scheduleDaily = $0 { true } else { false } })
    }

    @Test func timeChangeReschedules() async {
        let center = StubNotificationCenter()
        let scheduler = ReviewReminderScheduler(center: center)
        await scheduler.apply(enabled: true, minutes: 540)
        await scheduler.apply(enabled: true, minutes: 1200)
        let calls = center.calls
        #expect(calls.last == .scheduleDaily(identifier: id, hour: 20, minute: 0))
        for (index, call) in calls.enumerated() {
            if case .scheduleDaily = call {
                #expect(calls[index - 1] == .removePending(id))
            }
        }
    }
}
