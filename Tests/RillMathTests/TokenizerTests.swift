import XCTest
@testable import RillMath

/// TDD coverage for the RillMath lexer, command table, and parser.
///
/// These tests pin the public surface other modules link against:
/// ``MathToken``, ``MathLexer``, ``MathNode``, ``MathCommandTable``, and
/// ``MathParser``. They assert tokenization, command lookup, and the parsed
/// ``MathNode`` tree for the canonical LaTeX shapes LLMs emit.
final class TokenizerTests: XCTestCase {

    // MARK: - Lexer

    func testLexerSplitsCommandsBracesAndScripts() {
        let tokens = MathLexer.tokenize("\\frac{a}{b}")
        XCTAssertEqual(tokens, [
            .command("frac"),
            .leftBrace,
            .symbol("a"),
            .rightBrace,
            .leftBrace,
            .symbol("b"),
            .rightBrace,
        ])
    }

    func testLexerEmitsSuperscriptAndSubscript() {
        let tokens = MathLexer.tokenize("x^2_i")
        XCTAssertEqual(tokens, [
            .symbol("x"),
            .superscript,
            .symbol("2"),
            .subscript,
            .symbol("i"),
        ])
    }

    func testLexerHandlesBracketsForOptionalArgument() {
        let tokens = MathLexer.tokenize("\\sqrt[3]{x}")
        XCTAssertEqual(tokens, [
            .command("sqrt"),
            .leftBracket,
            .symbol("3"),
            .rightBracket,
            .leftBrace,
            .symbol("x"),
            .rightBrace,
        ])
    }

    func testLexerSkipsWhitespaceButEmitsSpaceCommand() {
        let tokens = MathLexer.tokenize("a \\, b")
        XCTAssertEqual(tokens, [
            .symbol("a"),
            .command(","),
            .symbol("b"),
        ])
    }

    func testLexerEmitsParenthesesAsSymbols() {
        let tokens = MathLexer.tokenize("(x)")
        XCTAssertEqual(tokens, [
            .symbol("("),
            .symbol("x"),
            .symbol(")"),
        ])
    }

    // MARK: - Command table

    func testCommandTableMapsGreek() {
        let entry = MathCommandTable.lookup("alpha")
        XCTAssertEqual(entry?.symbol, "\u{03B1}")
        XCTAssertEqual(entry?.category, .greek)
    }

    func testCommandTableMapsRelationsAndArrows() {
        XCTAssertEqual(MathCommandTable.lookup("leq")?.category, .relation)
        XCTAssertEqual(MathCommandTable.lookup("to")?.category, .arrow)
        XCTAssertEqual(MathCommandTable.lookup("times")?.category, .binaryOperator)
    }

    func testCommandTableHasRoughlyTwoHundredFiftyCommands() {
        XCTAssertGreaterThanOrEqual(MathCommandTable.count, 250)
    }

    func testCommandTableReturnsNilForUnknown() {
        XCTAssertNil(MathCommandTable.lookup("notarealcommand"))
    }

    /// Regression: `star`, `circ`, and `dagger` were each assigned twice in the
    /// table literal, with the later `sym(...)` assignment silently overriding
    /// the intended binary-operator entry (and, for `star`, swapping the glyph).
    /// They must keep their binary-operator category and correct glyphs.
    func testCommandTableHasNoDuplicateOverrideForBinaryOperators() {
        let star = MathCommandTable.lookup("star")
        XCTAssertEqual(star?.symbol, "\u{22C6}", "\\star must be the small filled star operator, not the white star.")
        XCTAssertEqual(star?.category, .binaryOperator)

        let circ = MathCommandTable.lookup("circ")
        XCTAssertEqual(circ?.symbol, "\u{2218}")
        XCTAssertEqual(circ?.category, .binaryOperator, "\\circ must keep binary-operator spacing.")

        let dagger = MathCommandTable.lookup("dagger")
        XCTAssertEqual(dagger?.symbol, "\u{2020}")
        XCTAssertEqual(dagger?.category, .binaryOperator, "\\dagger must keep binary-operator spacing.")
    }

    // MARK: - Parser

    func testParseFraction() {
        let nodes = MathParser.parse("\\frac{a}{b}")
        XCTAssertEqual(nodes, [
            .frac(numerator: [.symbol("a")], denominator: [.symbol("b")]),
        ])
    }

    func testParseScripts() {
        let nodes = MathParser.parse("x^2_i")
        XCTAssertEqual(nodes, [
            .scripts(
                base: [.symbol("x")],
                sup: [.symbol("2")],
                sub: [.symbol("i")]
            ),
        ])
    }

    func testParseSqrtWithIndex() {
        let nodes = MathParser.parse("\\sqrt[3]{x}")
        XCTAssertEqual(nodes, [
            .sqrt(index: [.symbol("3")], radicand: [.symbol("x")]),
        ])
    }

    func testParseSqrtWithoutIndex() {
        let nodes = MathParser.parse("\\sqrt{x}")
        XCTAssertEqual(nodes, [
            .sqrt(index: nil, radicand: [.symbol("x")]),
        ])
    }

    func testParseBigOperatorWithLimits() {
        let nodes = MathParser.parse("\\sum_{i=0}^n")
        XCTAssertEqual(nodes, [
            .bigOp(
                op: "\u{2211}",
                lower: [.symbol("i"), .symbol("="), .symbol("0")],
                upper: [.symbol("n")]
            ),
        ])
    }

    func testParseDelimited() {
        let nodes = MathParser.parse("\\left( \\frac a b \\right)")
        XCTAssertEqual(nodes, [
            .delimited(
                left: "(",
                right: ")",
                body: [.frac(numerator: [.symbol("a")], denominator: [.symbol("b")])]
            ),
        ])
    }

    func testParsePmatrix() {
        let nodes = MathParser.parse("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
        XCTAssertEqual(nodes, [
            .matrix(
                env: "pmatrix",
                rows: [
                    [[.symbol("1")], [.symbol("2")]],
                    [[.symbol("3")], [.symbol("4")]],
                ]
            ),
        ])
    }

    func testParseGreek() {
        let nodes = MathParser.parse("\\alpha")
        XCTAssertEqual(nodes, [.symbol("\u{03B1}")])
    }

    func testParseAccent() {
        let nodes = MathParser.parse("\\hat{x}")
        XCTAssertEqual(nodes, [.accent(kind: "hat", base: [.symbol("x")])])
    }

    func testParseSpace() {
        let nodes = MathParser.parse("a \\, b")
        XCTAssertEqual(nodes, [.symbol("a"), .space, .symbol("b")])
    }

    func testParseText() {
        let nodes = MathParser.parse("\\text{hello}")
        XCTAssertEqual(nodes, [.text("hello")])
    }

    /// Whitespace inside `\text{…}` is semantically significant and must survive
    /// tokenization (the lexer collapses whitespace between tokens, so the body
    /// is recovered verbatim from source).
    func testParseTextPreservesInternalSpaces() {
        XCTAssertEqual(MathParser.parse("\\text{a b}"), [.text("a b")])
        XCTAssertEqual(MathParser.parse("\\text{hello world}"), [.text("hello world")])
        XCTAssertEqual(MathParser.parse("\\text{  leading and trailing  }"),
                       [.text("  leading and trailing  ")])
    }

    /// A long run of consecutive stray structural tokens must not recurse
    /// (which would overflow the stack); the parser skips them iteratively and
    /// degrades gracefully without crashing.
    func testParseLongStrayTokenRunDoesNotOverflow() {
        let braces = MathParser.parse(String(repeating: "}", count: 200_000))
        XCTAssertEqual(braces, [])
        let rows = MathParser.parse(String(repeating: "\\\\", count: 100_000))
        XCTAssertEqual(rows, [])
        let amps = MathParser.parse(String(repeating: "&", count: 100_000))
        XCTAssertEqual(amps, [])
    }

    func testParseUnknownCommand() {
        let nodes = MathParser.parse("\\foobarbaz")
        XCTAssertEqual(nodes, [.unknown("foobarbaz")])
    }

    func testParseGroupedScriptBase() {
        let nodes = MathParser.parse("{ab}^2")
        XCTAssertEqual(nodes, [
            .scripts(
                base: [.group([.symbol("a"), .symbol("b")])],
                sup: [.symbol("2")],
                sub: nil
            ),
        ])
    }
}
