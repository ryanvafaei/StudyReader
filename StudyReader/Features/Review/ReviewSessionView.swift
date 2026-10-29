import SwiftUI

/// Renders a `ReviewSessionModel` by phase: start screen, card, summary or error. The daily review and the themed
/// sessions use it.
struct ReviewSessionView: View {
    let model: ReviewSessionModel
    let session: AppSession
    /// nil: the summary's Done ends the session and reloads the plan (daily review).
    let onDone: (() -> Void)?

    init(model: ReviewSessionModel, session: AppSession, onDone: (() -> Void)? = nil) {
        self.model = model
        self.session = session
        self.onDone = onDone
    }

    var body: some View {
        switch model.phase {
        case .idle:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let due, let new):
            if due + new > 0 {
                startScreen(due: due, new: new)
            } else {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("You're done for today. New cards come back after 4:00.")
                )
                .accessibilityIdentifier("review-empty")
            }
        case .reviewing:
            ReviewCardView(model: model, session: session)
        case .finished(let summary):
            ReviewSummaryView(summary: summary, model: model, onDone: onDone)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(LocalizedStringKey(message))
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await model.loadPlan() }
                }
                .accessibilityLabel(Text("Try Again"))
                .accessibilityIdentifier("review-retry")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func startScreen(due: Int, new: Int) -> some View {
        VStack(spacing: 12) {
            Text("Daily Review")
                .font(.largeTitle.bold())
            Text(ReviewStrings.cardsToReview(due + new))
                .font(.title3)
                .accessibilityIdentifier("review-card-count")
            Text(ReviewStrings.dueAndNew(due: due, new: new))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("review-due-new")
            Button("Start Review") {
                Task { await model.start() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(Text("Start Review"))
            .accessibilityIdentifier("review-start")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
