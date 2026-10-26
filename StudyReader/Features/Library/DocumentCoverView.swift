import AppKit
import SwiftUI

/// Cover for one document: the stored cover image when it loads, otherwise a generated card (SPEC F-01).
/// The image is read once per `coverPath` in `.task`, not on every body pass.
struct DocumentCoverView: View {
    let document: LibraryDocument
    let categoryName: String
    let fileStore: FileStore
    /// Cover file modification date. A change reloads the image even when `coverPath` is the same (Choose Image…
    /// or Reset Cover overwrite `cover.png` in place). Nil when the caller doesn't track it.
    let coverVersion: Date?

    @State private var coverImage: NSImage?

    init(document: LibraryDocument, categoryName: String, fileStore: FileStore, coverVersion: Date? = nil) {
        self.document = document
        self.categoryName = categoryName
        self.fileStore = fileStore
        self.coverVersion = coverVersion
    }

    /// Every cover shares one 3:4 portrait frame. The frame is a `Color.clear` base, so its size comes only from the
    /// proposed width, never from the image. Content is drawn in overlays: a blurred, dimmed copy fills the frame,
    /// and the cover is aspect-fit over it, so a landscape cover sits in the middle with blur above and below.
    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let coverImage {
                    Color.clear
                        .overlay {
                            Image(nsImage: coverImage)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 24)
                                .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                        }
                        .clipped()
                        .overlay {
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
            .task(id: CoverReloadKey(path: document.coverPath, version: coverVersion)) {
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

/// What the cover image depends on: the stored path and the cover file's modification date.
private struct CoverReloadKey: Hashable {
    let path: String?
    let version: Date?
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
