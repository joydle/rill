import XCTest
@testable import RillCore

/// Tests for the CommonMark/GFM inline parser: emphasis, code spans, links,
/// autolinks, images, inline math, citations, escapes, flanking rules, and the
/// streaming-tail "unbalanced trailing delimiter renders as literal" behavior.
final class InlineParserTests: XCTestCase {
    // MARK: Helpers

    private func parse(_ s: String, config: ParseConfig = .default) -> [Inline] {
        InlineParser.parse(Substring(s), config: config)
    }

    /// Flattens an inline tree to plain text (drops all formatting), for
    /// convenient structural-content assertions.
    private func plain(_ inlines: [Inline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let s): return s
            case .code(let s): return s
            case .mathInline(let s): return s
            case .rawHTML(let s): return s
            case .softBreak: return "\n"
            case .lineBreak: return "\n"
            case .emphasis(let c), .strong(let c), .strikethrough(let c):
                return plain(c)
            case .link(let l): return plain(l.inlines)
            case .image(let i): return i.alt
            case .citation(let c): return c.marker
            }
        }.joined()
    }

    // MARK: Plain text

    func testPlainText() {
        XCTAssertEqual(parse("hello world"), [.text("hello world")])
    }

    func testEmptyString() {
        XCTAssertEqual(parse(""), [])
    }

    // MARK: Emphasis

    func testSingleAsteriskEmphasis() {
        XCTAssertEqual(parse("*em*"), [.emphasis([.text("em")])])
    }

    func testUnderscoreEmphasis() {
        XCTAssertEqual(parse("_em_"), [.emphasis([.text("em")])])
    }

    func testDoubleAsteriskStrong() {
        XCTAssertEqual(parse("**strong**"), [.strong([.text("strong")])])
    }

    func testDoubleUnderscoreStrong() {
        XCTAssertEqual(parse("__strong__"), [.strong([.text("strong")])])
    }

    func testTripleAsteriskBothStrongEmphasis() {
        // *** => emphasis wrapping strong (CommonMark canonical: <em><strong>).
        XCTAssertEqual(parse("***both***"), [.emphasis([.strong([.text("both")])])])
    }

    func testEmphasisInsideText() {
        XCTAssertEqual(
            parse("a *b* c"),
            [.text("a "), .emphasis([.text("b")]), .text(" c")]
        )
    }

    func testNestedEmphasisInsideStrong() {
        // **a *b* c** => strong[ text(a ), em(b), text( c) ]
        XCTAssertEqual(
            parse("**a *b* c**"),
            [.strong([.text("a "), .emphasis([.text("b")]), .text(" c")])]
        )
    }

    func testStrongInsideEmphasis() {
        XCTAssertEqual(
            parse("*a **b** c*"),
            [.emphasis([.text("a "), .strong([.text("b")]), .text(" c")])]
        )
    }

    // MARK: Flanking rules

    func testIntrawordUnderscoreIsNotEmphasis() {
        // foo_bar_baz: underscores are not left/right flanking inside a word.
        XCTAssertEqual(parse("foo_bar_baz"), [.text("foo_bar_baz")])
    }

    func testIntrawordAsteriskIsEmphasis() {
        // foo*bar*baz: asterisks DO allow intraword emphasis per CommonMark.
        XCTAssertEqual(
            parse("foo*bar*baz"),
            [.text("foo"), .emphasis([.text("bar")]), .text("baz")]
        )
    }

    func testOpenerWithTrailingSpaceIsLiteral() {
        // "* not emphasis *" — a '*' followed by whitespace is not left-flanking.
        XCTAssertEqual(plain(parse("a * b * c")), "a * b * c")
        XCTAssertFalse(parse("a * b * c").contains { if case .emphasis = $0 { return true }; return false })
    }

    // MARK: Strikethrough (GFM)

    func testStrikethrough() {
        XCTAssertEqual(parse("~~del~~"), [.strikethrough([.text("del")])])
    }

    func testStrikethroughDisabledByConfig() {
        var cfg = ParseConfig.default
        cfg.strikethrough = false
        XCTAssertEqual(plain(parse("~~del~~", config: cfg)), "~~del~~")
    }

    func testSingleTildeIsLiteral() {
        XCTAssertEqual(plain(parse("a ~ b")), "a ~ b")
    }

    // MARK: Inline code

    func testInlineCode() {
        XCTAssertEqual(parse("`code`"), [.code("code")])
    }

    func testInlineCodeMultiBacktick() {
        // Double backtick span lets single backticks appear inside.
        XCTAssertEqual(parse("``a`b``"), [.code("a`b")])
    }

    func testInlineCodeStripsOneSurroundingSpace() {
        // CommonMark: a single leading+trailing space is stripped if content
        // is not all spaces.
        XCTAssertEqual(parse("` a `"), [.code("a")])
    }

    func testInlineCodeTakesPrecedenceOverEmphasis() {
        XCTAssertEqual(parse("`*not em*`"), [.code("*not em*")])
    }

    func testUnclosedBacktickIsLiteral() {
        XCTAssertEqual(parse("`code"), [.text("`code")])
    }

    // MARK: Escapes

    func testBackslashEscapeAsterisk() {
        XCTAssertEqual(parse("\\*not em\\*"), [.text("*not em*")])
    }

    func testBackslashEscapeBackslash() {
        XCTAssertEqual(parse("a\\\\b"), [.text("a\\b")])
    }

    func testBackslashBeforeNonPunctuationIsLiteralBackslash() {
        // "\a" — backslash before a non-escapable char stays literal.
        XCTAssertEqual(parse("\\a"), [.text("\\a")])
    }

    // MARK: Links

    func testLinkWithTitle() {
        let result = parse("[text](http://example.com \"the title\")")
        XCTAssertEqual(result.count, 1)
        guard case .link(let link) = result[0] else { return XCTFail("expected link") }
        XCTAssertEqual(link.inlines, [.text("text")])
        XCTAssertEqual(link.url, "http://example.com")
        XCTAssertEqual(link.title, "the title")
    }

    func testLinkWithoutTitle() {
        let result = parse("[text](http://example.com)")
        guard case .link(let link) = result.first else { return XCTFail("expected link") }
        XCTAssertEqual(link.url, "http://example.com")
        XCTAssertNil(link.title)
        XCTAssertEqual(link.inlines, [.text("text")])
    }

    func testLinkTextParsesInlines() {
        let result = parse("[*em*](u)")
        guard case .link(let link) = result.first else { return XCTFail("expected link") }
        XCTAssertEqual(link.inlines, [.emphasis([.text("em")])])
    }

    func testUnclosedLinkIsLiteral() {
        XCTAssertEqual(plain(parse("[text](url")), "[text](url")
    }

    // MARK: Autolinks

    func testAngleAutolink() {
        let result = parse("<https://example.com>")
        guard case .link(let link) = result.first else { return XCTFail("expected autolink") }
        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertEqual(link.inlines, [.text("https://example.com")])
    }

    func testBareURLAutolink() {
        let result = parse("see https://example.com now")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], .text("see "))
        guard case .link(let link) = result[1] else { return XCTFail("expected bare autolink") }
        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertEqual(result[2], .text(" now"))
    }

    func testBareURLTrailingPunctuationExcluded() {
        // Trailing '.' should not be part of the URL.
        let result = parse("visit https://example.com.")
        guard case .link(let link) = result.first(where: { if case .link = $0 { return true }; return false }) else {
            return XCTFail("expected autolink")
        }
        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertEqual(plain(result), "visit https://example.com.")
    }

    func testBareURLDisabledByConfig() {
        var cfg = ParseConfig.default
        cfg.bareURLAutolinks = false
        XCTAssertEqual(parse("see https://x.com", config: cfg), [.text("see https://x.com")])
    }

    // MARK: Images

    func testImage() {
        let result = parse("![alt text](http://img.png)")
        guard case .image(let image) = result.first else { return XCTFail("expected image") }
        XCTAssertEqual(image.alt, "alt text")
        XCTAssertEqual(image.url, "http://img.png")
        XCTAssertNil(image.title)
    }

    func testImageWithTitle() {
        let result = parse("![a](u \"t\")")
        guard case .image(let image) = result.first else { return XCTFail("expected image") }
        XCTAssertEqual(image.alt, "a")
        XCTAssertEqual(image.url, "u")
        XCTAssertEqual(image.title, "t")
    }

    // MARK: Inline math

    func testInlineMathBackslashParen() {
        XCTAssertEqual(parse("\\(x^2\\)"), [.mathInline("x^2")])
    }

    func testInlineMathDollar() {
        XCTAssertEqual(parse("$x^2$"), [.mathInline("x^2")])
    }

    func testInlineMathDollarWithSurroundingText() {
        XCTAssertEqual(
            parse("a $x$ b"),
            [.text("a "), .mathInline("x"), .text(" b")]
        )
    }

    func testLoneDollarIsLiteral() {
        XCTAssertEqual(parse("costs $5 today"), [.text("costs $5 today")])
    }

    func testDollarMathDisabledByConfig() {
        var cfg = ParseConfig.default
        cfg.dollarMath = false
        XCTAssertEqual(parse("$x$", config: cfg), [.text("$x$")])
    }

    // MARK: Citations

    func testNumericCitation() {
        let result = parse("see [1] here")
        XCTAssertEqual(result.count, 3)
        guard case .citation(let c) = result[1] else { return XCTFail("expected citation") }
        XCTAssertEqual(c.marker, "1")
        XCTAssertEqual(c.index, 1)
    }

    func testFootnoteCitation() {
        let result = parse("text[^note]")
        guard case .citation(let c) = result.last else { return XCTFail("expected footnote citation") }
        XCTAssertEqual(c.marker, "note")
        XCTAssertNil(c.index)
    }

    func testCitationDisabledByConfig() {
        var cfg = ParseConfig.default
        cfg.citations = false
        XCTAssertEqual(plain(parse("see [1]", config: cfg)), "see [1]")
    }

    // MARK: Unbalanced trailing delimiters (streaming tail)

    func testUnbalancedTrailingStrongIsLiteral() {
        XCTAssertEqual(parse("hello **"), [.text("hello **")])
    }

    func testUnbalancedTrailingEmphasisIsLiteral() {
        XCTAssertEqual(parse("hello *"), [.text("hello *")])
    }

    func testUnbalancedLeadingStrongWithTextIsLiteral() {
        // "**bold start" mid-stream: opener with no closer renders literally.
        XCTAssertEqual(plain(parse("**bold start")), "**bold start")
    }

    func testUnbalancedTrailingTildeIsLiteral() {
        XCTAssertEqual(parse("done ~~"), [.text("done ~~")])
    }

    // MARK: Wiring — blocks carry real inlines

    func testResolveInlinesOnDocumentBlocks() {
        let bytes = Array("# A *b* c\n\npara **bold** text".utf8)
        let blocks = InlineParser.resolveInlines(in: BlockLexer.lex(bytes[...]), config: .default)
        guard case .heading(let h) = blocks[0] else { return XCTFail("expected heading") }
        XCTAssertEqual(h.inlines, [.text("A "), .emphasis([.text("b")]), .text(" c")])
        guard case .paragraph(let p) = blocks[1] else { return XCTFail("expected paragraph") }
        XCTAssertEqual(p.inlines, [.text("para "), .strong([.text("bold")]), .text(" text")])
    }

    func testResolveInlinesLeavesCodeBlockUntouched() {
        let bytes = Array("```\n*not emphasis*\n```".utf8)
        let blocks = InlineParser.resolveInlines(in: BlockLexer.lex(bytes[...]), config: .default)
        guard case .codeBlock(let cb) = blocks[0] else { return XCTFail("expected code block") }
        XCTAssertEqual(cb.content, "*not emphasis*\n")
    }

    func testResolveInlinesNestedInQuoteAndList() {
        let bytes = Array("> quote *em*\n\n- item `code`".utf8)
        let blocks = InlineParser.resolveInlines(in: BlockLexer.lex(bytes[...]), config: .default)
        guard case .blockQuote(let bq) = blocks[0],
              case .paragraph(let qp) = bq.blocks.first else { return XCTFail("expected quoted paragraph") }
        XCTAssertEqual(qp.inlines, [.text("quote "), .emphasis([.text("em")])])
        guard case .list(let list) = blocks[1],
              case .paragraph(let ip) = list.items.first?.blocks.first else { return XCTFail("expected list paragraph") }
        XCTAssertEqual(ip.inlines, [.text("item "), .code("code")])
    }

    func testResolveInlinesInTableCells() {
        let bytes = Array("| *h* | b |\n| --- | --- |\n| `c` | d |".utf8)
        let blocks = InlineParser.resolveInlines(in: BlockLexer.lex(bytes[...]), config: .default)
        guard case .table(let table) = blocks[0] else { return XCTFail("expected table") }
        XCTAssertEqual(table.header[0], [.emphasis([.text("h")])])
        XCTAssertEqual(table.rows[0][0], [.code("c")])
    }

    // MARK: DelimiterStack unit

    func testDelimiterStackPushPop() {
        var stack = DelimiterStack()
        stack.push(DelimiterRun(char: "*", count: 2, canOpen: true, canClose: false, startIndex: 0))
        XCTAssertEqual(stack.count, 1)
        XCTAssertNotNil(stack.last)
        stack.removeAll()
        XCTAssertEqual(stack.count, 0)
    }
}
