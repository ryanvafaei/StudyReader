import Foundation
import Observation

/// The sidebar badge: how many cards today's daily plan holds (SPEC F-15). Observes the daily queue, so the count
/// follows every rating and every change to the cards. The view calls `observe()` once and keeps it running.
@MainActor @Observable
final class ReviewBadgeModel {
    private let environment: AppEnvironment
    private let settings: AppSettings
    private let calendar: Calendar

    private(set) var dailyDueCount = 0
    /// How many themed reviews are due today (SPEC F-20 AC2, ADR-0022). Shown on the Themed Reviews sidebar item.
    private(set) var themedDueCount = 0

    init(environment: AppEnvironment, settings: AppSettings, calendar: Calendar = .current) {
        self.environment = environment
        self.settings = settings
        self.calendar = calendar
    }

    /// Streams the daily queue and sets `dailyDueCount` to the size of the plan built from it. Returns when the
    /// task is cancelled or the observation fails.
    func observe() async {
        do {
            let observation = environment.reviewCardRepository.observeDailyQueue(now: environment.now, calendar: calendar)
            for try await snapshot in observation {
                dailyDueCount = DailyReviewBuilder.build(snapshot, limits: settings.dailyLimits).cardIds.count
            }
        } catch {
            Log.app.error("Review badge observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Streams the themed reviews and sets `themedDueCount` to how many are due now (ThemedReviewSchedule).
    /// Returns when the task is cancelled or the observation fails.
    func observeThemed() async {
        do {
            let observation = environment.themedReviewRepository.observeAll()
            for try await reviews in observation {
                let now = environment.now()
                themedDueCount = reviews.filter {
                    ThemedReviewSchedule.isDue($0, now: now, calendar: calendar)
                }.count
            }
        } catch {
            Log.app.error("Themed review badge observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
