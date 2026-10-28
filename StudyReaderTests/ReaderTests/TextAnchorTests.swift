import Foundation
import Testing
@testable import StudyReader

@Suite("TextAnchor")
struct TextAnchorTests {
    private func range(of needle: String, in text: String, occurrence: Int = 0) -> NSRange {
        let ns = text as NSString
        var found = NSRange(location: NSNotFound, length: 0)
        var searchFrom = 0
        for _ in 0...occurrence {
            found = ns.range(of: needle, options: .literal, range: NSRange(location: searchFrom, length: ns.length - searchFrom))
            searchFrom = found.location + 1
        }
        return found
    }

    @Test func anchorCapturesContext() {
        let text = "The quick brown fox jumps over the lazy dog"
        let anchor = TextAnchoring.anchor(for: range(of: "brown fox", in: text), in: text, sourceVersion: 3)
        #expect(anchor.text == "brown fox")
        #expect(anchor.prefix == "The quick ")
        #expect(anchor.suffix == " jumps over the lazy dog")
        #expect(anchor.start == 10)
        #expect(anchor.length == 9)
        #expect(anchor.sourceVersion == 3)

        let long = String((0..<100).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })
        let middle = NSRange(location: 40, length: 10)
        let longAnchor = TextAnchoring.anchor(for: middle, in: long, sourceVersion: 1)
        #expect(longAnchor.prefix.utf16.count == 32)
        #expect(longAnchor.suffix.utf16.count == 32)
        #expect(longAnchor.prefix == (long as NSString).substring(with: NSRange(location: 8, length: 32)))
        #expect(longAnchor.suffix == (long as NSString).substring(with: NSRange(location: 50, length: 32)))
    }

    @Test func composedCharactersNotSplit() {
        let emoji = "\u{1F44D}\u{1F3FD}"   // thumbs up + skin tone modifier: 4 UTF-16 units, one character
        #expect(emoji.utf16.count == 4)

        for fillerCount in 28...34 {
            let filler = String(repeating: "a", count: fillerCount)
            // The emoji sits at units [1, 5) of the prefix region and, mirrored, [fillerCount, fillerCount + 4) of the suffix region.
            let text = "b" + emoji + filler + "SELECTED" + filler + emoji + "b"
            let anchor = TextAnchoring.anchor(for: range(of: "SELECTED", in: text), in: text, sourceVersion: 1)

            #expect(!anchor.prefix.contains("\u{FFFD}"))
            #expect(!anchor.suffix.contains("\u{FFFD}"))
            if (28...31).contains(fillerCount) {
                #expect(anchor.prefix == emoji + filler, "prefix, filler \(fillerCount)")
            } else {
                #expect(anchor.prefix == String(filler.suffix(32)), "prefix, filler \(fillerCount)")
            }
            if (28...31).contains(fillerCount) {
                #expect(anchor.suffix == filler + emoji, "suffix, filler \(fillerCount)")
            } else {
                #expect(anchor.suffix == String(filler.prefix(32)), "suffix, filler \(fillerCount)")
            }
        }
    }

    @Test func unchangedWhenSame() {
        let text = "Alpha beta gamma delta"
        let anchor = TextAnchoring.anchor(for: range(of: "gamma", in: text), in: text, sourceVersion: 2)
        #expect(TextAnchoring.resolve(anchor, in: text, currentVersion: 2) == .unchanged)

        let newVersion = TextAnchoring.resolve(anchor, in: text, currentVersion: 3)
        var expected = anchor
        expected.sourceVersion = 3
        #expect(newVersion == .moved(expected))
    }

    @Test func reanchorWithPrefixSuffix() throws {
        let old = "Intro.\n\nGradient descent minimizes the loss.  It is iterative.\n\nGradient descent minimizes the loss again."
        let target = "Gradient descent minimizes the loss"
        let anchor = TextAnchoring.anchor(for: range(of: target, in: old), in: old, sourceVersion: 1)
        #expect(anchor.prefix == "Intro.\n\n")

        let new = "New preface paragraph\u{2026} \nIntro. Gradient descent minimizes the loss. It is iterative. Gradient descent minimizes the loss again."
        let resolution = TextAnchoring.resolve(anchor, in: new, currentVersion: 2)
        guard case .moved(let moved) = resolution else {
            Issue.record("expected .moved, got \(resolution)")
            return
        }
        let newRange = NSRange(location: moved.start, length: moved.length)
        #expect(newRange == range(of: target, in: new, occurrence: 0))
        #expect((new as NSString).substring(with: newRange) == target)
        #expect(moved.sourceVersion == 2)
        #expect(moved.text == anchor.text)
        #expect(moved.prefix == anchor.prefix)
        #expect(moved.suffix == anchor.suffix)
    }

    @Test func prefersNearbyOccurrence() throws {
        let filler = String(repeating: "-", count: 100)
        let old = "abc" + filler + "abc" + filler
        let anchor = TextAnchor(start: 90, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)
        let resolution = TextAnchoring.resolve(anchor, in: old, currentVersion: 1)
        #expect(resolution == .moved(TextAnchor(start: 103, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)))

        let early = TextAnchor(start: 20, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)
        let earlyResolution = TextAnchoring.resolve(early, in: old, currentVersion: 1)
        #expect(earlyResolution == .moved(TextAnchor(start: 0, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)))
    }

    @Test func nearbyOccurrenceBeatsBetterScoredFarOne() {
        let filler = String(repeating: "-", count: 3_000)
        let text = "PRE target" + filler + "xx target"
        let nearStart = text.utf16.count - 6
        // The stored range runs past the end, so the text is searched. The far occurrence (offset 4) matches the
        // prefix better but lies outside the 2,000-unit window around the old start.
        let stale = TextAnchor(start: nearStart + 2, length: 6, text: "target", prefix: "PRE ", suffix: "", sourceVersion: 1)
        let expected = TextAnchor(start: nearStart, length: 6, text: "target", prefix: "PRE ", suffix: "", sourceVersion: 1)
        #expect(TextAnchoring.resolve(stale, in: text, currentVersion: 1) == .moved(expected))
    }

    @Test func farMoveUsesWholeText() throws {
        let old = "Start of notes. The needle sentence lives here. End of notes."
        let anchor = TextAnchoring.anchor(for: range(of: "needle sentence", in: old), in: old, sourceVersion: 1)
        let moved = String(repeating: "x", count: 5_000) + old
        let resolution = TextAnchoring.resolve(anchor, in: moved, currentVersion: 2)
        guard case .moved(let result) = resolution else {
            Issue.record("expected .moved, got \(resolution)")
            return
        }
        #expect(result.start == anchor.start + 5_000)
        #expect(result.length == anchor.length)
        #expect(result.sourceVersion == 2)
    }

    @Test func orphanedWhenGone() {
        let old = "Alpha beta gamma delta"
        let anchor = TextAnchoring.anchor(for: range(of: "gamma", in: old), in: old, sourceVersion: 1)
        #expect(TextAnchoring.resolve(anchor, in: "Alpha beta delta", currentVersion: 2) == .orphaned)
        #expect(TextAnchoring.resolve(anchor, in: "", currentVersion: 2) == .orphaned)
        let empty = TextAnchor(start: 0, length: 0, text: "", prefix: "", suffix: "", sourceVersion: 1)
        #expect(TextAnchoring.resolve(empty, in: old, currentVersion: 1) == .orphaned)
    }

    @Test func multilineSelectionAcrossChangedWhitespace() {
        let old = "Alpha beta\n\ngamma delta epsilon"
        let anchor = TextAnchoring.anchor(for: range(of: "beta\n\ngamma", in: old), in: old, sourceVersion: 1)
        #expect(anchor.text == "beta\n\ngamma")

        let new = "Intro Alpha beta gamma delta epsilon"
        guard case .moved(let moved) = TextAnchoring.resolve(anchor, in: new, currentVersion: 2) else {
            Issue.record("expected .moved")
            return
        }
        #expect((new as NSString).substring(with: NSRange(location: moved.start, length: moved.length)) == "beta gamma")

        let wider = "Intro Alpha beta \t\n gamma delta epsilon"
        guard case .moved(let widerMoved) = TextAnchoring.resolve(anchor, in: wider, currentVersion: 2) else {
            Issue.record("expected .moved")
            return
        }
        #expect((wider as NSString).substring(with: NSRange(location: widerMoved.start, length: widerMoved.length)) == "beta \t\n gamma")
    }

    @Test func positionKeyIsStart() {
        let anchor = TextAnchor(start: 42, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)
        #expect(TextAnchoring.positionKey(for: anchor) == 42)
    }

    // MARK: - Resolver

    @Test func resolverMatchesResolveForAllCases() {
        let old = "Intro.\n\nGradient descent minimizes the loss.  It is iterative.\n\nGradient descent minimizes the loss again."
        let target = "Gradient descent minimizes the loss"
        let gradient = TextAnchoring.anchor(for: range(of: target, in: old), in: old, sourceVersion: 1)
        let reflowed = "New preface paragraph\u{2026} \nIntro. Gradient descent minimizes the loss. It is iterative. Gradient descent minimizes the loss again."

        let filler = String(repeating: "-", count: 100)
        let twice = "abc" + filler + "abc" + filler
        let nearby = TextAnchor(start: 90, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)
        let early = TextAnchor(start: 20, length: 3, text: "abc", prefix: "", suffix: "", sourceVersion: 1)

        let notes = "Start of notes. The needle sentence lives here. End of notes."
        let needle = TextAnchoring.anchor(for: range(of: "needle sentence", in: notes), in: notes, sourceVersion: 1)
        let farText = String(repeating: "x", count: 5_000) + notes

        let alpha = "Alpha beta gamma delta"
        let gamma = TextAnchoring.anchor(for: range(of: "gamma", in: alpha), in: alpha, sourceVersion: 1)
        let empty = TextAnchor(start: 0, length: 0, text: "", prefix: "", suffix: "", sourceVersion: 1)

        let multiline = "Alpha beta\n\ngamma delta epsilon"
        let lines = TextAnchoring.anchor(for: range(of: "beta\n\ngamma", in: multiline), in: multiline, sourceVersion: 1)

        let cases: [(anchor: TextAnchor, text: String, version: Int)] = [
            (gradient, old, 1), (gradient, old, 2), (gradient, reflowed, 2),
            (nearby, twice, 1), (early, twice, 1),
            (needle, farText, 2),
            (gamma, alpha, 1), (gamma, alpha, 2), (gamma, "Alpha beta delta", 2), (gamma, "", 2), (empty, alpha, 1),
            (lines, "Intro Alpha beta gamma delta epsilon", 2), (lines, "Intro Alpha beta \t\n gamma delta epsilon", 2)
        ]
        for (index, item) in cases.enumerated() {
            var resolver = TextAnchoring.Resolver(text: item.text)
            #expect(
                resolver.resolve(item.anchor, currentVersion: item.version)
                    == TextAnchoring.resolve(item.anchor, in: item.text, currentVersion: item.version),
                "case \(index)"
            )
        }
    }

    @Test func fastPathDoesNotNormalise() {
        let text = "Alpha beta gamma delta. Alpha beta gamma delta, again."
        let unchanged = TextAnchoring.anchor(for: range(of: "gamma", in: text), in: text, sourceVersion: 2)
        let stale = TextAnchor(start: 500, length: 5, text: "gamma", prefix: "beta ", suffix: " delta", sourceVersion: 2)
        let stale2 = TextAnchor(start: 700, length: 5, text: "Alpha", prefix: "", suffix: " beta", sourceVersion: 2)

        var resolver = TextAnchoring.Resolver(text: text)
        #expect(resolver.resolve(unchanged, currentVersion: 2) == .unchanged)
        #expect(resolver.hasBuiltNormalizedText == false)

        guard case .moved = resolver.resolve(stale, currentVersion: 2) else {
            Issue.record("expected .moved")
            return
        }
        #expect(resolver.hasBuiltNormalizedText)
        #expect(resolver.normalizedBuildCount == 1)

        guard case .moved = resolver.resolve(stale2, currentVersion: 2) else {
            Issue.record("expected .moved")
            return
        }
        #expect(resolver.normalizedBuildCount == 1)
    }

    @Test func windowScanFindsNearbyWithoutFullScan() {
        let needle = "needle sentence"
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 40_000)   // about 1 MB
        let nearOffset = 600_000
        let units = Array(filler.utf16)
        let head = String(decoding: units[0..<nearOffset], as: UTF16.self)
        let tail = String(decoding: units[nearOffset...], as: UTF16.self)
        let text = needle + " " + head + needle + " " + tail
        #expect(text.utf16.count > 1_000_000)

        let nearStart = needle.utf16.count + 1 + nearOffset
        let stale = TextAnchor(start: nearStart + 700, length: needle.utf16.count, text: needle, prefix: "", suffix: "", sourceVersion: 1)
        var resolver = TextAnchoring.Resolver(text: text)
        let resolution = resolver.resolve(stale, currentVersion: 1)
        #expect(resolution == .moved(TextAnchor(
            start: nearStart, length: needle.utf16.count, text: needle, prefix: "", suffix: "", sourceVersion: 1
        )))

        let wholeText = TextAnchoring.resolve(stale, in: text, currentVersion: 1)
        #expect(wholeText == resolution)
    }
}
