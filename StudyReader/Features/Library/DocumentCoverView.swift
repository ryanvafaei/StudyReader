import AppKit
import SwiftUI

/// Cover for one document: the stored cover image when it loads, otherwise a generated card (SPEC F-01).
/// The image is read once per `coverPath` in `.task`, not on every body pass.
struct DocumentCoverView: View {
    let document: LibraryDocument
    let categoryName: String
    let fileStore: FileStore

    @State private var coverImage: NSImage?

    init(document: LibraryDocument, categoryName: String, fileStore: FileStore) {
        self.document = document
        self.categoryName = categoryName
        self.fileStore = fileStore
    }

    var body: some View {
        ZStack {
            if let coverImage {
                Image(nsImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                GeneratedCoverView(title: document.title, fileType: document.fileType)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: document.coverPath) {
            coverImage = loadCoverImage()
        }
    }

    private func loadCoverImage() -> NSImage? {
        guard let coverPath = document.coverPath,
              let url = fileStore.url(forRelativePath: coverPath) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// Fallback cover: a rounded card tinted by file type with the title and a document icon.
private struct GeneratedCoverView: View {
    let title: String
    let fileType: FileType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint)
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var tint: Color {
        switch fileType {
        case .pdf: Color.secondary.opacity(0.2)
        case .markdown: Color.accentColor.opacity(0.15)
        }
    }
}
