import SwiftUI

/// The end-of-session summary (SPEC F-15).
struct ReviewSummaryView: View {
    let summary: ReviewSummary
    let model: ReviewSessionModel
    let onDone: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text("Session complete")
                .font(.largeTitle.bold())
            Text(ReviewStrings.reviewed(summary.reviewed))
                .font(.title3)
                .accessibilityIdentifier("review-summary-reviewed")
            Text("Remembered \(summary.rememberedPercent)%")
                .accessibilityIdentifier("review-summary-remembered")
            Text("Due tomorrow: \(summary.dueTomorrow)")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("review-summary-tomorrow")
            Button("Done") {
                if let onDone {
                    onDone()
                } else {
                    model.endSession()
                    Task { await model.loadPlan() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            .accessibilityLabel(Text("Done"))
            .accessibilityIdentifier("review-done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
