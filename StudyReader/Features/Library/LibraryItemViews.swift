import SwiftUI

/// Display text shared by the grid cards and the list table.
enum LibraryItemFormat {
    static func highlights(_ count: Int) -> String {
        count == 1 ? String(localized: "1 highlight") : String(localized: "\(count) highlights")
    }

    /// Progress clamped to 0...1 and rounded to a whole percent.
    static func percent(_ progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }

    /// "title, author, category, N highlights, NN percent read"; empty author is skipped.
    static func accessibilityLabel(for item: LibraryItem) -> String {
        let document = item.document
        let author: String? = document.author.isEmpty ? nil : document.author
        let percentRead = String(localized: "\(percent(document.progress)) percent read")
        return [document.title, author, item.categoryName, highlights(item.highlightCount), percentRead]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// One grid card: cover with the extraction status on its bottom edge, then text, progress and last opened.
/// The status sits in a sibling of the cover, not on it, because the cover is hidden from accessibility.
struct LibraryGridCard: View {
    let item: LibraryItem
    let fileStore: FileStore
    /// Cover file modification date from `LibraryModel.coverVersions`; a change reloads the cover.
    let coverVersion: Date?
    let isSelected: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                DocumentCoverView(
                    document: item.document,
                    categoryName: item.categoryName,
                    fileStore: fileStore,
                    coverVersion: coverVersion
                )
                LibraryStatusBadge(status: item.document.extractionStatus, onRetry: onRetry)
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                // The title always reserves two lines and the author one, so metadata rows line up across a row.
                Text(item.document.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                Text(item.document.author.isEmpty ? " " : item.document.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(item.document.author.isEmpty)
                Text("\(item.categoryName) · \(LibraryItemFormat.highlights(item.highlightCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LibraryProgressRow(progress: item.document.progress)
                LibraryLastOpenedText(date: item.document.lastOpenedAt)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(LibraryItemFormat.accessibilityLabel(for: item))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

/// Progress bar with the percentage, used by grid cards and the list table.
struct LibraryProgressRow: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 6) {
            LibraryProgressBar(fraction: min(max(progress, 0), 1))
            Text("\(LibraryItemFormat.percent(progress)) %")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// A thin bar that is empty at 0. Drawn by hand because `ProgressView` keeps a minimum fill width.
struct LibraryProgressBar: View {
    /// Already clamped to 0...1.
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// "Last opened" as a relative date, or "Never opened".
struct LibraryLastOpenedText: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Never opened")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// "Added" as a date, styled like "Last opened".
struct LibraryAddedText: View {
    let date: Date

    var body: some View {
        Text(date, style: .date)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Extraction status for the grid: a material pill on the cover's bottom edge while pending or failed.
/// Renders nothing when extraction is done.
struct LibraryStatusBadge: View {
    let status: ExtractionStatus
    let onRetry: () -> Void

    var body: some View {
        if case .done = status {
            EmptyView()
        } else {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .done:
            EmptyView()
        case .pending:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Indexing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            HStack(spacing: 8) {
                Text("Text extraction failed")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry", action: onRetry)
                    .controlSize(.small)
                    .accessibilityLabel("Retry text extraction")
            }
        }
    }
}

/// Title cell for the list: the title truncates, the compact status never does.
struct LibraryTitleCell: View {
    let title: String
    let status: ExtractionStatus
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            LibraryCompactStatus(status: status, onRetry: onRetry)
        }
    }
}

/// Compact extraction status for the list: a small spinner while pending, a warning icon and Retry when failed.
struct LibraryCompactStatus: View {
    let status: ExtractionStatus
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .done:
            EmptyView()
        case .pending:
            ProgressView()
                .controlSize(.small)
                .help("Indexing…")
                .accessibilityLabel("Indexing…")
                .fixedSize()
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("Text extraction failed")
                    .accessibilityLabel("Text extraction failed")
                Button("Retry", action: onRetry)
                    .controlSize(.small)
                    .help("Retry text extraction")
                    .accessibilityLabel("Retry text extraction")
            }
            .fixedSize()
        }
    }
}

/// Context menu for one document. Used by both the grid and the table.
struct LibraryItemMenu: View {
    let item: LibraryItem
    /// Set by T50. Nil keeps "Edit Metadata…" disabled.
    let editMetadata: (@MainActor (String) -> Void)?
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Open", action: onOpen)

        Button("Edit Metadata…") {
            editMetadata?(item.id)
        }
        .disabled(editMetadata == nil)

        Button("Reveal Original in Finder", action: onReveal)
            .disabled(item.document.originalBookmark == nil)

        Divider()

        Button("Delete…", role: .destructive, action: onDelete)
    }
}
