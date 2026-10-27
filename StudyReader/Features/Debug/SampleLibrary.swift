#if DEBUG
import CoreGraphics
import CoreText
import Foundation

/// DEBUG-only sample library for the Debug menu. Not compiled into Release.
///
/// Sample documents use reserved canonical UUIDs, so seeding is idempotent and removal can only match
/// documents this seeder created. Everything goes through the real repositories and FileStore; nothing here
/// issues SQL and the schema is untouched. Sample categories are never created: only built-in ones are used.
struct SampleLibrary: Sendable {
    /// Prefix on every sample document title and sample tag name.
    static let titlePrefix = "Sample · "

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Creates each sample that doesn't exist yet. Returns the number created (0 when all seven exist).
    func seed() async throws -> Int {
        var created = 0
        for sample in Self.samples {
            if try await environment.documentRepository.fetch(id: sample.id) != nil {
                continue
            }
            try await create(sample)
            created += 1
        }
        Log.files.info("Seeded \(created, privacy: .public) sample documents")
        return created
    }

    /// Deletes the sample documents through DocumentRepository.delete (row, highlights, folder), then sample tags
    /// that no document or highlight uses. Returns the number of documents removed.
    func removeSamples() async throws -> Int {
        var removed = 0
        for sample in Self.samples {
            guard let document = try await environment.documentRepository.fetch(id: sample.id),
                  document.title.hasPrefix(Self.titlePrefix) else {
                continue
            }
            if try await environment.documentRepository.delete(id: sample.id, fileStore: environment.fileStore) {
                removed += 1
            }
        }
        try await removeUnusedSampleTags()
        Log.files.info("Removed \(removed, privacy: .public) sample documents")
        return removed
    }

    // MARK: - Creation

    private func create(_ sample: Sample) async throws {
        let now = environment.now()
        let fileStore = environment.fileStore
        let ext = sample.fileType == .pdf ? "pdf" : "md"

        // A folder left by an interrupted run has no row; clear it so creation starts clean.
        try? fileStore.deleteDocumentFolder(documentId: sample.id)
        _ = try fileStore.createDocumentFolder(documentId: sample.id)

        let originalURL = try fileStore.originalFileURL(documentId: sample.id, fileType: sample.fileType)
        var bookmark: Data?
        if sample.hasOriginal {
            try Self.writeOriginal(sample, to: originalURL)
            bookmark = try? originalURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        var coverPath: String?
        if sample.hasCover {
            let coverURL = try fileStore.coverURL(documentId: sample.id)
            try CoverRenderer.renderPDFPage(fileAt: originalURL, pageIndex: 0, to: coverURL)
            coverPath = fileStore.relativePath(for: coverURL)
        }

        let document = LibraryDocument(
            id: sample.id,
            title: Self.titlePrefix + sample.title,
            author: sample.author,
            categoryId: sample.category.id,
            fileType: sample.fileType,
            fileHash: "sample-\(sample.id)",
            originalFilename: sample.hasOriginal ? "sample.\(ext)" : "moved.\(ext)",
            originalBookmark: bookmark,
            storedPath: fileStore.relativePath(for: originalURL) ?? "\(sample.id)/original.\(ext)",
            pageCount: sample.fileType == .pdf ? sample.pages.count : nil,
            coverPath: coverPath,
            coverSource: .automatic,
            pdfPosition: sample.fileType == .pdf && sample.progress > 0 ? PDFPosition(pageIndex: 1, offsetY: 120) : nil,
            textPosition: sample.fileType == .markdown && sample.progress > 0 ? 40 : nil,
            progress: sample.progress,
            addedAt: now.addingTimeInterval(-14 * 86_400),
            lastOpenedAt: sample.openedDaysAgo.map { now.addingTimeInterval(-Double($0) * 86_400) }
        )
        try await environment.documentRepository.insert(document)

        let tagIds = try await tagIds(for: sample.tags, now: now)
        try await environment.tagRepository.setTags(tagIds, forDocument: sample.id)

        for spec in sample.highlights {
            if let highlight = Self.highlight(for: spec, in: sample, now: now) {
                try await environment.highlightRepository.insert(highlight)
            }
        }

        switch sample.extraction {
        case .done:
            let version = sample.fileType == .pdf ? PDFTextExtractor.version : MarkdownRenderer.version
            _ = try await environment.documentTextRepository.replaceUnits(
                Self.units(for: sample),
                documentId: sample.id,
                version: version
            )
        case .failed:
            try await environment.documentTextRepository.markFailed(documentId: sample.id)
        case .pending:
            break
        }
    }

    private func tagIds(for names: [String], now: Date) async throws -> [String] {
        var ids: [String] = []
        for name in names {
            let tag = try await environment.tagRepository.findOrCreate(name: Self.titlePrefix + name, at: now)
            ids.append(tag.id)
        }
        return ids
    }

    private func removeUnusedSampleTags() async throws {
        var usages: [TagUsage] = []
        for try await value in environment.tagRepository.observeUsage() {
            usages = value
            break
        }
        for usage in usages where usage.tag.name.hasPrefix(Self.titlePrefix)
            && usage.documentCount == 0
            && usage.highlightCount == 0 {
            try await environment.tagRepository.delete(id: usage.tag.id)
        }
    }

    // MARK: - Files

    private static func writeOriginal(_ sample: Sample, to url: URL) throws {
        switch sample.fileType {
        case .pdf:
            try writePDF(of: sample, to: url)
        case .markdown:
            try markdownText(of: sample).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Plain PDF with one text line per entry, drawn with CoreText (thread-safe, no PDFKit). Page size, font size
    /// and line spacing come from the sample.
    private static func writePDF(of sample: Sample, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: sample.pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw SampleLibraryError.pdfContextUnavailable
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, sample.fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        for lines in sample.pages {
            context.beginPDFPage(nil)
            for (line, text) in lines.enumerated() {
                let attributed = NSAttributedString(string: text, attributes: attributes) as CFAttributedString
                context.textPosition = CGPoint(x: 72, y: baseline(line, in: sample))
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    // MARK: - Content helpers

    private static func markdownText(of sample: Sample) -> String {
        sample.paragraphs.joined(separator: "\n\n")
    }

    /// The string the reader shows for a Markdown sample (`MarkdownRenderer` output).
    private static func renderedString(of sample: Sample) -> String {
        MarkdownRenderer.render(MarkdownDocumentSource(markdown: markdownText(of: sample), documentId: nil, fileStore: nil))
            .string
    }

    private static func units(for sample: Sample) -> [DocumentText] {
        if sample.fileType == .markdown {
            return [
                DocumentText(
                    documentId: sample.id,
                    unitIndex: 0,
                    startOffset: 0,
                    text: markdownText(of: sample)
                )
            ]
        }
        var result: [DocumentText] = []
        var offset = 0
        for (index, lines) in sample.pages.enumerated() {
            let text = lines.joined(separator: "\n")
            result.append(DocumentText(documentId: sample.id, unitIndex: index, startOffset: offset, text: text))
            offset += text.utf16.count + 1
        }
        return result
    }

    /// PDF line i sits at this baseline, 92 pt below the top edge; `lineRect` covers the same line.
    private static func baseline(_ line: Int, in sample: Sample) -> CGFloat {
        sample.pageSize.height - 92 - CGFloat(line) * sample.lineStep
    }

    private static func lineRect(_ line: Int, in sample: Sample) -> CGRect {
        CGRect(
            x: 72,
            y: baseline(line, in: sample) - 5,
            width: sample.pageSize.width - 144,
            height: sample.lineStep - 4
        )
    }

    private static func highlight(for spec: SampleHighlight, in sample: Sample, now: Date) -> Highlight? {
        switch spec.spot {
        case let .pdfLine(page, line):
            let text = sample.pages[page][line]
            let anchor = PDFAnchor(
                pages: [PDFAnchor.PageRects(pageIndex: page, rects: [CGRectCodable(lineRect(line, in: sample))])],
                text: text,
                prefix: "",
                suffix: ""
            )
            return Highlight(
                id: UUID().uuidString,
                documentId: sample.id,
                kind: .text,
                view: .pdf,
                color: spec.color,
                text: text,
                richText: RichTextMarkdown.escape(text),
                note: spec.note,
                pageIndex: page,
                positionKey: Double(page) + Double(line) / 1000,
                anchor: .pdf(anchor),
                createdAt: now,
                updatedAt: now
            )
        case let .phrase(phrase):
            // Offsets and context are those of the rendered string (what the reader shows and anchors against), not
            // of the file: the renderer separates blocks with one newline, the file with a blank line.
            let rendered = renderedString(of: sample)
            let range = NSString(string: rendered).range(of: phrase)
            guard range.location != NSNotFound else {
                Log.files.error("Sample phrase not found in its rendered text")
                return nil
            }
            let anchor = TextAnchoring.anchor(for: range, in: rendered, sourceVersion: MarkdownRenderer.version)
            return Highlight(
                id: UUID().uuidString,
                documentId: sample.id,
                kind: .text,
                view: .markdown,
                color: spec.color,
                text: phrase,
                richText: RichTextMarkdown.escape(phrase),
                note: spec.note,
                pageIndex: nil,
                positionKey: TextAnchoring.positionKey(for: anchor),
                anchor: .text(anchor),
                createdAt: now,
                updatedAt: now
            )
        }
    }

    // MARK: - Sample definitions

    private enum Extraction: Sendable {
        case done, failed, pending
    }

    private enum Spot: Sendable {
        case pdfLine(page: Int, line: Int)
        case phrase(String)
    }

    private struct SampleHighlight: Sendable {
        let color: HighlightColor
        let spot: Spot
        var note = ""
    }

    private struct Sample: Sendable {
        let id: String
        let title: String
        let author: String
        let category: BuiltinCategory
        let fileType: FileType
        let pages: [[String]]
        let paragraphs: [String]
        let tags: [String]
        let hasOriginal: Bool
        let hasCover: Bool
        let extraction: Extraction
        let progress: Double
        /// nil means the document has never been opened.
        let openedDaysAgo: Int?
        let highlights: [SampleHighlight]
        /// PDF page size in points. Defaults to US Letter portrait.
        var pageSize = CGSize(width: 612, height: 792)
        /// PDF body font size in points.
        var fontSize: CGFloat = 14
        /// Distance between PDF text lines in points.
        var lineStep: CGFloat = 26
    }

    /// Seven documents: PDF and Markdown, portrait and landscape, with and without covers, varied tags, highlights
    /// and progress. Covers the states: never opened, done, failed, pending, and missing original (no bookmark).
    private static let samples: [Sample] = [
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000001",
            title: "Lecture 1: Cell Biology",
            author: "Dr. A. Rivera",
            category: .lectureSlides,
            fileType: .pdf,
            pages: [
                [
                    "Cell membranes are phospholipid bilayers.",
                    "Proteins embedded in the membrane move materials.",
                    "Osmosis moves water across a semipermeable membrane."
                ],
                [
                    "Mitochondria produce ATP through oxidative phosphorylation.",
                    "The electron transport chain pumps protons.",
                    "Cristae increase the inner membrane surface area."
                ],
                [
                    "The nucleus stores DNA and controls gene expression.",
                    "Ribosomes translate mRNA into proteins.",
                    "The endoplasmic reticulum folds and transports proteins."
                ]
            ],
            paragraphs: [],
            tags: ["exam", "midterm"],
            hasOriginal: true,
            hasCover: true,
            extraction: .done,
            progress: 0.4,
            openedDaysAgo: 2,
            highlights: [
                SampleHighlight(color: .yellow, spot: .pdfLine(page: 0, line: 1)),
                SampleHighlight(color: .green, spot: .pdfLine(page: 1, line: 2), note: "Check this for the quiz"),
                SampleHighlight(color: .blue, spot: .pdfLine(page: 2, line: 0))
            ]
        ),
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000002",
            title: "Paper: Sparse Attention Study",
            author: "M. Chen",
            category: .paper,
            fileType: .pdf,
            pages: [
                [
                    "Sparse attention restricts each query to a subset of keys.",
                    "Local windows capture nearby context cheaply.",
                    "Global tokens summarize the whole sequence."
                ],
                [
                    "Block sparse patterns trade accuracy for memory.",
                    "We report results on long-document benchmarks."
                ]
            ],
            paragraphs: [],
            tags: [],
            hasOriginal: true,
            hasCover: true,
            extraction: .done,
            progress: 0,
            openedDaysAgo: nil,
            highlights: []
        ),
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000003",
            title: "Notes: Gradient Descent",
            author: "",
            category: .notes,
            fileType: .markdown,
            pages: [],
            paragraphs: [
                "Gradient descent updates parameters in the direction that lowers the loss.",
                "The learning rate controls the size of each step, and too large a step can diverge.",
                "Stochastic gradient descent estimates the gradient from a small batch of examples.",
                "Momentum keeps a running average of past gradients to smooth the path."
            ],
            tags: ["exam", "reviewed", "mid-term"],
            hasOriginal: true,
            hasCover: false,
            extraction: .done,
            progress: 0.75,
            openedDaysAgo: 1,
            highlights: [
                SampleHighlight(color: .yellow, spot: .phrase("lowers the loss")),
                SampleHighlight(color: .green, spot: .phrase("too large a step can diverge"), note: "Diverges"),
                SampleHighlight(color: .blue, spot: .phrase("small batch of examples")),
                SampleHighlight(color: .pink, spot: .phrase("running average"))
            ]
        ),
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000004",
            title: "Paper: Retrieval Notes",
            author: "",
            category: .paper,
            fileType: .markdown,
            pages: [],
            paragraphs: [
                "Retrieval augmented generation combines a search step with a language model.",
                "The retriever ranks passages by similarity to the query."
            ],
            tags: ["reviewed"],
            hasOriginal: true,
            hasCover: false,
            extraction: .failed,
            progress: 0.1,
            openedDaysAgo: 5,
            highlights: []
        ),
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000005",
            title: "Book chapter: Probability",
            author: "J. Park",
            category: .bookChapter,
            fileType: .pdf,
            pages: [
                [
                    "Probability assigns a number between zero and one to each event.",
                    "Conditional probability is defined as P(A and B) over P(B)."
                ],
                [
                    "Bayes rule inverts a conditional probability.",
                    "Independent events satisfy P(A and B) = P(A) P(B)."
                ]
            ],
            paragraphs: [],
            tags: [],
            hasOriginal: true,
            hasCover: false,
            extraction: .pending,
            progress: 0.1,
            openedDaysAgo: 10,
            highlights: [
                SampleHighlight(color: .pink, spot: .pdfLine(page: 0, line: 0))
            ]
        ),
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000006",
            title: "Lab manual: Pendulum",
            author: "",
            category: .other,
            fileType: .pdf,
            pages: [
                [
                    "Lab 3: measure the period of a pendulum.",
                    "Record ten swings for each length and average the times."
                ]
            ],
            paragraphs: [],
            tags: [],
            hasOriginal: false,
            hasCover: false,
            extraction: .done,
            progress: 0.5,
            openedDaysAgo: 3,
            highlights: [
                SampleHighlight(color: .purple, spot: .pdfLine(page: 0, line: 1))
            ]
        ),
        Sample(
            id: "5A4D0000-0000-4000-8000-000000000007",
            title: "Slides: Membrane Transport",
            author: "Dr. A. Rivera",
            category: .lectureSlides,
            fileType: .pdf,
            pages: [
                [
                    "Diffusion moves molecules down a gradient.",
                    "Small nonpolar molecules cross the bilayer easily."
                ],
                [
                    "Channels let ions pass through the membrane.",
                    "Pumps spend ATP to move ions against a gradient."
                ],
                [
                    "Endocytosis brings material into the cell.",
                    "Exocytosis releases material from vesicles."
                ]
            ],
            paragraphs: [],
            tags: ["exam"],
            hasOriginal: true,
            hasCover: true,
            extraction: .done,
            progress: 0.2,
            openedDaysAgo: 4,
            highlights: [
                SampleHighlight(color: .yellow, spot: .pdfLine(page: 1, line: 0))
            ],
            // 16:9 slide deck. The cover is aspect-fit inside the shared 3:4 frame, so it shows the whole slide.
            pageSize: CGSize(width: 960, height: 540),
            fontSize: 28,
            lineStep: 52
        )
    ]
}

private enum SampleLibraryError: Error {
    case pdfContextUnavailable
}
#endif
