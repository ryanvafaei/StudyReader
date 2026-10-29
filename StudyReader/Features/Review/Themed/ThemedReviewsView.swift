import SwiftUI

/// The sidebar "Themed Reviews" section (SPEC F-20): the list of reviews, or the running session in its place.
/// LibraryView is not mounted here (RootView replaces the detail column), so its Return/Escape buttons are gone:
/// Return on a selected row is only the List's primary action and Escape does nothing.
struct ThemedReviewsView: View {
    let session: AppSession
    @State private var model: ThemedReviewsModel
    @State private var pendingDelete: ThemedReview?

    init(session: AppSession) {
        self.session = session
        _model = State(initialValue: ThemedReviewsModel(session: session))
    }

    var body: some View {
        @Bindable var model = model
        return Group {
            if let running = model.runningSession {
                runningView(running)
            } else {
                listView
            }
        }
        .navigationTitle("Themed Reviews")
        .task { await model.observe() }
        .sheet(item: $model.editorRequest) { request in
            ThemedReviewEditorSheet(reviewId: request.reviewId, environment: session.environment)
        }
        .confirmationDialog(
            pendingDelete.map { String(localized: "Delete “\($0.name)”?") } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { review in
            Button("Delete", role: .destructive) {
                Task { await model.delete(review.id) }
            }
            .accessibilityIdentifier("themed-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The review cards stay; only this themed review is removed.")
        }
    }

    // MARK: List

    @ViewBuilder
    private var listView: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("themed-error")
            }
            Divider()
            if model.reviews.isEmpty && model.hasLoaded {
                ContentUnavailableView {
                    Label("No themed reviews", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Create one to review a chosen set of highlights, for example before an exam.")
                } actions: {
                    Button("New Themed Review…") { model.newReview() }
                        .accessibilityLabel(Text("New Themed Review"))
                        .accessibilityIdentifier("themed-empty-new")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("themed-empty")
            } else {
                List(model.reviews, selection: $model.selection) { review in
                    row(review)
                        .tag(review.id)
                }
                .accessibilityIdentifier("themed-list")
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let review = model.reviews.first(where: { $0.id == id }) {
                        Button("Run") { Task { await model.run(id) } }
                        Button("Edit…") { model.edit(id) }
                        Button("Duplicate") { Task { await model.duplicate(id) } }
                        Button("Delete…", role: .destructive) { pendingDelete = review }
                    }
                } primaryAction: { ids in
                    if let id = ids.first {
                        Task { await model.run(id) }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Themed Reviews")
                .font(.title2.bold())
            Spacer()
            Button {
                model.newReview()
            } label: {
                Label("New Themed Review…", systemImage: "plus")
            }
            .accessibilityLabel(Text("New Themed Review"))
            .accessibilityIdentifier("themed-new")
        }
        .padding(16)
    }

    private func row(_ review: ThemedReview) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(review.name)
                    .font(.headline)
                Text(model.intervalSummary(review))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let last = review.lastCompletedAt {
                    Text("Last done \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isDue(review) {
                Text("Due")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    .accessibilityLabel(Text("Due"))
                    .accessibilityIdentifier("themed-row-due")
            }
            Button("Run") { Task { await model.run(review.id) } }
                .accessibilityLabel(Text("Run \(review.name)"))
                .accessibilityIdentifier("themed-row-run")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(review.name))
        .accessibilityIdentifier("themed-row")
    }

    // MARK: Running

    private func runningView(_ running: ReviewSessionModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.stopRunning()
                } label: {
                    Label("Themed Reviews", systemImage: "chevron.left")
                }
                .accessibilityLabel(Text("Back to Themed Reviews"))
                .accessibilityIdentifier("themed-back")
                Spacer()
                if let name = running.themedReviewName {
                    Text(name)
                        .font(.headline)
                        .accessibilityIdentifier("themed-running-name")
                }
                Spacer()
            }
            .padding(12)
            Divider()
            ReviewSessionView(model: running, session: session, onDone: { model.stopRunning() })
        }
    }
}
