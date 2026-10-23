import CoreGraphics
import Foundation
import ImageIO
import Markdown
import Testing

@Suite struct MarkdownFixturesTests {

    private func allNodes(in markup: any Markup) -> [any Markup] {
        [markup] + markup.children.flatMap { allNodes(in: $0) }
    }

    @Test func fixturesLoadFromBundle() throws {
        for name in ["all-elements", "front-matter", "rich-inline", "persian"] {
            let url = try MarkdownFixtures.url(name)
            #expect(url.pathExtension == "md")
            let text = try MarkdownFixtures.string(name)
            #expect(!text.isEmpty)
        }
        do {
            _ = try MarkdownFixtures.url("no-such-fixture")
            Issue.record("Expected MarkdownFixtureError.missing for an unknown fixture")
        } catch MarkdownFixtureError.missing(let name) {
            #expect(name == "no-such-fixture")
        }
    }

    @Test func allElementsCoversEveryElement() throws {
        let document = Document(parsing: try MarkdownFixtures.string("all-elements"))
        let nodes = allNodes(in: document)

        let headingLevels = Set(nodes.compactMap { ($0 as? Heading)?.level })
        #expect(headingLevels == [1, 2, 3, 4, 5, 6])

        #expect(nodes.contains { $0 is Paragraph })
        #expect(nodes.contains { $0 is Emphasis })
        #expect(nodes.contains { $0 is Strong })
        #expect(nodes.contains { $0 is InlineCode })
        #expect(nodes.contains { $0 is Strikethrough })
        #expect(nodes.contains { $0 is Link })
        #expect(nodes.contains { $0 is BlockQuote })
        #expect(nodes.contains { $0 is UnorderedList })
        #expect(nodes.contains { $0 is OrderedList })

        let checkboxes = nodes.compactMap { ($0 as? ListItem)?.checkbox }
        #expect(checkboxes.contains(.unchecked))
        #expect(checkboxes.contains(.checked))

        #expect(nodes.contains { $0 is Table })

        let codeLanguages = nodes.compactMap { ($0 as? CodeBlock)?.language }
        #expect(codeLanguages.contains("swift"))

        #expect(nodes.contains { $0 is ThematicBreak })

        let imageSources = nodes.compactMap { ($0 as? Image)?.source }
        #expect(imageSources.count == 3)
        #expect(imageSources.contains("images/diagram.png"))
        #expect(imageSources.contains("images/missing.png"))
        #expect(imageSources.contains("https://example.com/remote.png"))
    }

    @Test func frontMatterFixtureShape() throws {
        let text = try MarkdownFixtures.string("front-matter")
        #expect(text.hasPrefix("---\n"))
        let firstLines = text.components(separatedBy: "\n").prefix(5).joined(separator: "\n")
        #expect(firstLines.contains("title: Gradient Descent Notes"))
        #expect(firstLines.contains("author: Ada Lovelace"))
    }

    @Test func richInlineExact() throws {
        let text = try MarkdownFixtures.string("rich-inline")
        #expect(text == "a **bold** and *italic* word with `code`\n")
    }

    @Test func persianContainsZWNJ() throws {
        let text = try MarkdownFixtures.string("persian")
        #expect(text.unicodeScalars.contains("\u{200C}"))
        #expect(text.contains("gradient"))
    }

    @Test func folderWithImages() throws {
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let folder = notes.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(notes.lastPathComponent == "notes.md")
        #expect(FileManager.default.fileExists(atPath: notes.path))

        let diagram = folder.appending(path: "images/diagram.png")
        let source = try #require(CGImageSourceCreateWithURL(diagram as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 8)
        #expect(image.height == 8)

        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "images/missing.png").path))
    }
}
