import Foundation
import Observation

/// What the themed review editor sheet shows: a new review or an existing one.
enum ThemedEditorRequest: Identifiable, Equatable {
    case new
    case edit(String)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let reviewId): reviewId
        }
    }

    var reviewId: String? {
        switch self {
        case .new: nil
        case .edit(let reviewId): reviewId
        }
    }
}

/// State behind the Themed Reviews section (SPEC F-20): the list, its actions and the running session (T124).
@MainActor @Observable
final class ThemedReviewsModel {
    private(set) var reviews: [ThemedReview] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    /// Selected review id.
    var selection: String?
    /// Drives the editor sheet.
    var editorRequest: ThemedEditorRequest?
    /// The running session, if any. While non-nil the section shows the session instead of the list.
    private(set) var runningSession: ReviewSessionModel?

    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private let calendar: Calendar

    init(session: AppSession, calendar: Calendar = .current) {
        self.session = session
        self.calendar = calendar
    }

    private var environment: AppEnvironment { session.environment }

    /// Streams the themed reviews (sorted by name) until the task is cancelled.
    func observe() async {
        do {
            for try await list in environment.themedReviewRepository.observeAll() {
                reviews = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if let selection, !reviews.contains(where: { $0.id == selection }) {
                    self.selection = nil
                }
                hasLoaded = true
            }
        } catch {
            Log.app.error("Themed reviews observation failed: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "The themed reviews couldn't be loaded.")
            hasLoaded = true
        }
    }

    func isDue(_ review: ThemedReview) -> Bool {
        ThemedReviewSchedule.isDue(review, now: environment.now(), calendar: calendar)
    }

    /// "Every day", "Every N days" (N >= 2) or the short weekday names in the calendar's order ("Mon, Thu").
    func intervalSummary(_ review: ThemedReview) -> String {
        let interval = review.interval
        switch interval.kind {
        case .daily:
            return String(localized: "Every day")
        case .everyNDays:
            let n = interval.n ?? 1
            return n <= 1 ? String(localized: "Every day") : String(localized: "Every \(n) days")
        case .weekdays:
            let selected = Set(interval.weekdays ?? [])
            let first = calendar.firstWeekday
            let ordered = (0..<7).map { (first - 1 + $0) % 7 + 1 }.filter { selected.contains($0) }
            return ordered.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    func newReview() {
        editorRequest = .new
    }

    func edit(_ id: String) {
        editorRequest = .edit(id)
    }

    func duplicate(_ id: String) async {
        do {
            let copy = try await environment.themedReviewRepository.duplicate(id: id, at: environment.now())
            errorMessage = nil
            selection = copy.id
        } catch {
            errorMessage = String(localized: "The themed review couldn't be duplicated.")
        }
    }

    func delete(_ id: String) async {
        do {
            try await environment.themedReviewRepository.delete(id: id)
            errorMessage = nil
            if selection == id { selection = nil }
        } catch {
            errorMessage = String(localized: "The themed review couldn't be deleted.")
        }
    }

    func run(_ id: String) async {
        let running = ReviewSessionModel(session: session, context: .themed(id: id))
        runningSession = running
        errorMessage = nil
        await running.loadPlan()
    }

    /// Back to the list. An unfinished session stays uncompleted (ADR-0022).
    func stopRunning() {
        runningSession = nil
    }
}
