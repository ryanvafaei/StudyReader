import Observation
import SwiftUI

/// Live category list and writes for Settings > Review (F-17, F-19). Display state only.
@MainActor @Observable
final class ReviewSettingsModel {
    private(set) var categories: [DocumentCategory] = []
    private(set) var errorMessage: String?

    private let repository: CategoryRepository

    init(categories: CategoryRepository) {
        self.repository = categories
    }

    func observe() async {
        do {
            for try await list in repository.observeAll() {
                categories = list
            }
        } catch {
            guard !Task.isCancelled else { return }
            Log.app.error("Category list failed to load in Review settings")
            errorMessage = String(localized: "The category couldn't be changed.")
        }
    }

    func setFrequency(_ frequency: ReviewFrequency, for categoryId: String) async {
        do {
            _ = try await repository.setFrequency(id: categoryId, frequency)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The category couldn't be changed.")
        }
    }

    func setAutoCreateCards(_ enabled: Bool, for categoryId: String) async {
        do {
            try await repository.setAutoCreateCards(id: categoryId, enabled)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The category couldn't be changed.")
        }
    }
}

/// Settings > Review tab (SPEC F-22).
struct ReviewSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var model: ReviewSettingsModel
    @Environment(\.calendar) private var calendar

    init(settings: AppSettings, categories: CategoryRepository) {
        self.settings = settings
        _model = State(initialValue: ReviewSettingsModel(categories: categories))
    }

    var body: some View {
        Form {
            Section("Daily review") {
                Stepper(value: $settings.reviewDailyLimit, in: SettingsStore.reviewDailyLimitRange) {
                    Text("Daily limit: \(settings.reviewDailyLimit)")
                }
                .accessibilityLabel("Daily limit")

                Stepper(value: $settings.reviewNewPerDay, in: SettingsStore.reviewNewPerDayRange) {
                    Text("New cards per day: \(settings.reviewNewPerDay)")
                }
                .accessibilityLabel("New cards per day")

                Toggle("Show four rating buttons (Again, Hard, Good, Easy)", isOn: $settings.showFourRatingButtons)
                    .accessibilityLabel("Show four rating buttons")
            }

            Section("Reminder") {
                Toggle("Remind me to review", isOn: $settings.reviewReminderEnabled)
                    .accessibilityLabel("Remind me to review")

                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .disabled(!settings.reviewReminderEnabled)
                    .accessibilityLabel("Reminder time")
            }

            Section {
                ForEach(model.categories) { category in
                    CategoryReviewRow(category: category, model: model)
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Off suspends the category's cards. Cards for new highlights are created only when this is on and the frequency isn't Off.")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
        .task { await model.observe() }
    }

    /// `reviewReminderMinutes` as a time on today's local date.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let minutes = settings.reviewReminderMinutes
                return calendar.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                settings.reviewReminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

private struct CategoryReviewRow: View {
    let category: DocumentCategory
    let model: ReviewSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Picker("Frequency", selection: frequency) {
                    Text("Off").tag(ReviewFrequency.off)
                    Text("Low").tag(ReviewFrequency.low)
                    Text("Normal").tag(ReviewFrequency.normal)
                    Text("High").tag(ReviewFrequency.high)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(String(localized: "Frequency for \(category.name)"))
            }
            Toggle("Create cards automatically", isOn: autoCreate)
                .accessibilityLabel(String(localized: "Create cards automatically for \(category.name)"))
        }
    }

    private var frequency: Binding<ReviewFrequency> {
        Binding(
            get: { category.frequency },
            set: { newValue in
                Task { await model.setFrequency(newValue, for: category.id) }
            }
        )
    }

    private var autoCreate: Binding<Bool> {
        Binding(
            get: { category.autoCreateCards },
            set: { newValue in
                Task { await model.setAutoCreateCards(newValue, for: category.id) }
            }
        )
    }
}
