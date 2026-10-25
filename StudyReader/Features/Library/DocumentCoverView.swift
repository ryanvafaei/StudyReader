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

    /// Every cover shares one 3:4 portrait frame. The frame is a `Color.clear` base, so its size comes only from the
    /// proposed width, never from the image. Content is drawn in an overlay: a landscape cover is aspect-fit in the
    /// middle, and a blurred, dimmed copy of it fills the rest of the frame.
    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let coverImage {
                    ZStack {
                        Image(nsImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 24)
                            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                            .clipped()
                        Image(nsImage: coverImage)
                            .resizable()
                            .scaledToFit()
                    }
                } else {
                    GeneratedCoverView(title: document.title, fileType: document.fileType)
                }
            }
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
