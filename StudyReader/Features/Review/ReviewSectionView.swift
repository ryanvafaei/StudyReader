import SwiftUI

/// The sidebar "Review" section: today's daily review (SPEC F-15). The model lives in `AppSession`, so a running
/// session or its summary survives leaving the section.
struct ReviewSectionView: View {
    let session: AppSession

    var body: some View {
        let model = session.dailyReviewModel()
        ReviewSessionView(model: model, session: session)
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
