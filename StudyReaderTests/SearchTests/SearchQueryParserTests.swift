import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite struct SearchQueryParserTests {
    private static let combiningAcute = "\u{0301}"

    /// Ordinary inputs from the spec, each of which must produce a valid expression.
    private static let sampleInputs = [
        "neural network",
        "\"gradient descent\" loss",
        "\"open phrase",
        "back*",
        "cnn -rnn",
        "-\"deep nets\" ml",
        "say\"hi",
        "NOT AND NEAR",
        "neural \"gradient descent\" back* -cnn",
    ]

    /// Adversarial inputs: FTS5 syntax, quotes with combining marks, control characters and long strings.
    private static let adversarialInputs: [String] = [
        "title:x",
        "^a",
        "(a)",
        "a:b",
        "a OR b",
        "NOT AND NEAR",
        "\u{201C}curly\u{201D} \u{2018}quotes\u{2019}",
        "a\u{0001}b",
        "-*",
        "a**",
        "\"a\"\(combiningAcute)",
        "say\"\(combiningAcute)hi",
        "\"a\"\(combiningAcute) OR title:x \"\(combiningAcute)",
        String(repeating: "ab\"", count: 16_667),
        "\"" + String(repeating: "lorem ", count: 8_000) + "\"",
    ]

    /// Inputs with no positive term. They have no expression, so nothing is sent to MATCH.
    private static let nilExpressionInputs = ["-*"]

    /// The text of an FTS5 expression outside its string literals, or nil when a literal is left open.
    /// Inside a literal `""` is one quote and a single `"` closes it.
    private static func unquotedText(of expression: String) -> String? {
        let scalars = Array(expression.unicodeScalars)
        var outside = ""
        var isInside = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                if isInside, index + 1 < scalars.count, scalars[index + 1] == "\"" {
                    index += 2
                    continue
                }
                isInside.toggle()
            } else if !isInside {
                outside.unicodeScalars.append(scalar)
            }
            index += 1
        }
        return isInside ? nil : outside
    }

    /// Records an issue unless every quote in the expression is balanced and the only operators outside
    /// string literals are the ones the parser emits (AND, NOT and the prefix star).
    private static func expectStructurallySafe(_ expression: String) {
        guard let outside = unquotedText(of: expression) else {
            Issue.record("Unclosed string literal in \(expression)")
            return
        }
        let tokens = Set(outside.split(separator: " ").map(String.init))
        #expect(tokens.isSubset(of: ["AND", "NOT", "*"]), "Unexpected text outside literals in \(expression)")
    }

    @Test func wordsAreANDed() {
        #expect(SearchQueryParser.matchExpression(for: "neural network") == "\"neural\" AND \"network\"")
    }

    @Test func phrases() {
        #expect(SearchQueryParser.matchExpression(for: "\"gradient descent\" loss")
            == "\"gradient descent\" AND \"loss\"")
        #expect(SearchQueryParser.matchExpression(for: "\"open phrase") == "\"open phrase\"")
    }

    @Test func prefix() {
        #expect(SearchQueryParser.matchExpression(for: "back*") == "\"back\"*")
        #expect(SearchQueryParser.matchExpression(for: "*") == nil)
        #expect(SearchQueryParser.matchExpression(for: "-*") == nil)
        #expect(SearchQueryParser.matchExpression(for: "a**") == "\"a*\"*")
    }

    @Test func exclusion() {
        #expect(SearchQueryParser.matchExpression(for: "cnn -rnn") == "\"cnn\" NOT \"rnn\"")
        #expect(SearchQueryParser.matchExpression(for: "-\"deep nets\" ml") == "\"ml\" NOT \"deep nets\"")
        #expect(SearchQueryParser.matchExpression(for: "-only") == nil)
    }

    @Test func quotesAreEscaped() {
        #expect(SearchQueryParser.matchExpression(for: "say\"hi") == "\"say\"\"hi\"")
        #expect(SearchQueryParser.matchExpression(for: "say\"\"hi") == "\"say\"\"\"\"hi\"")
        #expect(SearchQueryParser.matchExpression(for: "\"a\"\"b\"") == "\"a\" AND \"b\"")
    }

    @Test func quoteFollowedByCombiningMarkIsEscaped() {
        let mark = Self.combiningAcute
        // Bare word: the quote belongs to the word and is doubled even though a combining mark follows it.
        #expect(SearchQueryParser.matchExpression(for: "say\"\(mark)hi") == "\"say\"\"\(mark)hi\"")
        // Phrase: the closing quote ends the phrase even though a combining mark follows it.
        #expect(SearchQueryParser.matchExpression(for: "\"a\"\(mark) OR title:x \"\(mark)")
            == "\"a\" AND \"\(mark)\" AND \"OR\" AND \"title:x\" AND \"\(mark)\"")
        #expect(SearchQueryParser.matchExpression(for: "\"x\"\(mark) OR y\"")
            == "\"x\" AND \"\(mark)\" AND \"OR\" AND \"y\"\"\"")
        #expect(SearchQueryParser.terms(in: "\"a\"\(mark)")
            == [
                .init(text: "a", isPhrase: true, isPrefix: false, isNegated: false),
                .init(text: "\(mark)", isPhrase: false, isPrefix: false, isNegated: false),
            ])
    }

    @Test func adversarialWordsAreQuoted() {
        #expect(SearchQueryParser.matchExpression(for: "title:x") == "\"title:x\"")
        #expect(SearchQueryParser.matchExpression(for: "^a") == "\"^a\"")
        #expect(SearchQueryParser.matchExpression(for: "(a)") == "\"(a)\"")
        #expect(SearchQueryParser.matchExpression(for: "a:b") == "\"a:b\"")
        #expect(SearchQueryParser.matchExpression(for: "a OR b") == "\"a\" AND \"OR\" AND \"b\"")
        #expect(SearchQueryParser.matchExpression(for: "a\u{0001}b") == "\"a\u{0001}b\"")
    }

    @Test func expressionsAreStructurallySafe() {
        for input in Self.sampleInputs + Self.adversarialInputs {
            guard let expression = SearchQueryParser.matchExpression(for: input) else { continue }
            Self.expectStructurallySafe(expression)
        }
    }

    @Test func keywordsAreQuoted() {
        #expect(SearchQueryParser.matchExpression(for: "NOT AND NEAR") == "\"NOT\" AND \"AND\" AND \"NEAR\"")
    }

    @Test func whitespaceOnly() {
        #expect(SearchQueryParser.matchExpression(for: "   ") == nil)
        #expect(SearchQueryParser.matchExpression(for: "-") == nil)
        #expect(SearchQueryParser.matchExpression(for: "\"   \"") == nil)
        #expect(SearchQueryParser.matchExpression(for: "") == nil)
    }

    @Test func termsAreParsed() {
        #expect(SearchQueryParser.terms(in: "-x \"a b\" back* c")
            == [
                .init(text: "x", isPhrase: false, isPrefix: false, isNegated: true),
                .init(text: "a b", isPhrase: true, isPrefix: false, isNegated: false),
                .init(text: "back", isPhrase: false, isPrefix: true, isNegated: false),
                .init(text: "c", isPhrase: false, isPrefix: false, isNegated: false),
            ])
    }

    @Test func firstPositiveTerm() {
        #expect(SearchQueryParser.firstPositiveTerm(in: "-x \"a b\" c") == "a b")
        #expect(SearchQueryParser.firstPositiveTerm(in: "-x") == nil)
        #expect(SearchQueryParser.firstPositiveTerm(in: "   ") == nil)
    }

    @Test func expressionsAreValidFTS() throws {
        let database = try AppDatabase.makeInMemory()
        for input in Self.sampleInputs + Self.adversarialInputs {
            guard let expression = SearchQueryParser.matchExpression(for: input) else {
                #expect(Self.nilExpressionInputs.contains(input), "Unexpected nil expression for \(input)")
                continue
            }
            let count = try database.reader.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM documentText_fts WHERE documentText_fts MATCH ?",
                    arguments: [expression]) ?? -1
            }
            #expect(count >= 0, "Expression for \(input) failed to run: \(expression)")
        }
    }
}
