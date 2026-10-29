import SwiftUI

/// The sidebar "Review" section: a switch between today's daily review (SPEC F-15) and the Flashcards list
/// (SPEC F-17). The models live in `AppSession`, so a running session, its summary and the flashcard filters survive
/// leaving the section or switching the mode.
struct ReviewSectionView: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(spacing: 0) {
            Picker("Review mode", selection: $session.reviewSectionMode) {
                Text("Daily Review").tag(ReviewSectionMode.daily)
                Text("Flashcards").tag(ReviewSectionMode.flashcards)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 8)
            .accessibilityLabel("Review mode")
            .accessibilityIdentifier("flashcards-mode")
            Divider()
            switch session.reviewSectionMode {
            case .daily:
                dailyReview
            case .flashcards:
                FlashcardsView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dailyReview: some View {
        let model = session.dailyReviewModel()
        return ReviewSessionView(model: model, session: session)
            .task {
                switch model.phase {
                case .idle, .ready, .failed:
                    await model.loadPlan()
                case .reviewing, .finished:
                    break
                }
            }
    }
}
