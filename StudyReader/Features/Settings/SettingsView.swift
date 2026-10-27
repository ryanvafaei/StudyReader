import AppKit
import SwiftUI

/// Settings scene content. Shows a progress view until the library has opened and the session exists.
struct SettingsRootView: View {
    let launchModel: AppLaunchModel

    var body: some View {
        if let session = launchModel.session {
            SettingsView(session: session)
        } else {
            ProgressView("Opening library…")
                .frame(width: SettingsView.width, height: 160)
        }
    }
}

/// Settings window (⌘,). Phase 1 tabs: General, Reading, Data. Review and Google come later (F-22).
struct SettingsView: View {
    static let width: CGFloat = 520

    let session: AppSession

    var body: some View {
        TabView {
            GeneralSettingsView(session: session)
                .tabItem { Label("General", systemImage: "gearshape") }
            ReadingSettingsView(settings: session.settings)
                .tabItem { Label("Reading", systemImage: "book") }
            DataSettingsView(rootURL: session.environment.fileStore.rootURL)
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: Self.width)
        .scenePadding()
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var categoryOptions: SettingsCategoryOptions

    init(session: AppSession) {
        self.settings = session.settings
        _categoryOptions = State(initialValue: SettingsCategoryOptions(repository: session.environment.categoryRepository))
    }

    var body: some View {
        Form {
            Section {
                Picker("Default category for imports", selection: categorySelection) {
                    ForEach(categoryOptions.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .disabled(categoryOptions.categories.isEmpty)
                .accessibilityLabel("Default category for imports")

                Toggle("Highlight automatically when I select text", isOn: $settings.autoHighlight)
                    .accessibilityLabel("Highlight automatically when I select text")

                if categoryOptions.loadFailed {
                    Text("Categories couldn't load.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Highlight colors") {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    ColorLabelRow(color: color, settings: settings)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .task { await categoryOptions.observe() }
    }

    /// Shows the fallback when the saved category is missing. Writes the stored setting only on a user pick.
    private var categorySelection: Binding<String?> {
        Binding(
            get: {
                SettingsCategoryOptions.effectiveSelection(
                    saved: settings.defaultCategoryId,
                    in: categoryOptions.categories
                )
            },
            set: { newValue in
                if let id = newValue {
                    settings.defaultCategoryId = id
                }
            }
        )
    }
}

/// One highlight color: a swatch and an editable label. Commits on submit and on focus loss.
private struct ColorLabelRow: View {
    let color: HighlightColor
    let settings: AppSettings

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            TextField("Label", text: $draft)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .accessibilityLabel(String(localized: "Label for \(HighlightPalette.name(color)) highlights"))
        } label: {
            Label {
                Text(HighlightPalette.title(color))
            } icon: {
                Circle()
                    .fill(HighlightPalette.color(color))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { draft = settings.label(for: color) }
    }

    /// Empty input restores the default label (SettingsStore.setColorLabel).
    private func commit() {
        settings.setLabel(draft, for: color)
        draft = settings.label(for: color)
    }
}

private struct ReadingSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Invert PDF colors in dark mode", isOn: $settings.invertPDFInDarkMode)
                .accessibilityLabel("Invert PDF colors in dark mode")
        }
        .formStyle(.grouped)
    }
}

private struct DataSettingsView: View {
    let rootURL: URL

    var body: some View {
        Form {
            LabeledContent("Library location") {
                Text(rootURL.path(percentEncoded: false))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([rootURL])
            }
            .accessibilityLabel("Reveal library in Finder")
        }
        .formStyle(.grouped)
    }
}
