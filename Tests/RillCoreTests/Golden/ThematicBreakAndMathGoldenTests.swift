import XCTest
@testable import RillCore

/// Golden tests for thematic breaks, math blocks, and raw HTML blocks.
final class ThematicBreakAndMathGoldenTests: XCTestCase {
    func testThematicBreaks() {
        for marker in ["---", "***", "___", "- - -", "*****", "____"] {
            let blocks = Golden.lex(marker)
            XCTAssertEqual(blocks.count, 1, "for \(marker)")
            guard case .thematicBreak = blocks[0] else {
                return XCTFail("expected thematic break for \(marker), got \(blocks[0])")
            }
        }
    }

    func testTwoDashesIsNotThematicBreak() {
        let blocks = Golden.lex("--")
        XCTAssertEqual(Golden.paragraphText(blocks[0]), "--")
    }

    func testDollarMathBlockClosed() {
        let blocks = Golden.lex("$$\na^2 + b^2 = c^2\n$$")
        XCTAssertEqual(blocks.count, 1)
        guard case .mathBlock(let m) = blocks[0] else {
            return XCTFail("expected math block, got \(blocks[0])")
        }
        XCTAssertEqual(m.latex, "a^2 + b^2 = c^2")
        XCTAssertTrue(m.isClosed)
    }

    func testDollarMathBlockUnclosed() {
        let blocks = Golden.lex("$$\nx = 1")
        guard case .mathBlock(let m) = blocks[0] else {
            return XCTFail("expected math block")
        }
        XCTAssertFalse(m.isClosed)
        XCTAssertEqual(m.latex, "x = 1")
    }

    func testInlineDollarPairOnOneLineIsMathBlock() {
        let blocks = Golden.lex("$$E = mc^2$$")
        guard case .mathBlock(let m) = blocks[0] else {
            return XCTFail("expected math block, got \(blocks[0])")
        }
        XCTAssertTrue(m.isClosed)
        XCTAssertEqual(m.latex, "E = mc^2")
    }

    func testBracketMathBlockClosed() {
        let blocks = Golden.lex("\\[\n\\int x\\,dx\n\\]")
        guard case .mathBlock(let m) = blocks[0] else {
            return XCTFail("expected math block, got \(blocks[0])")
        }
        XCTAssertTrue(m.isClosed)
        XCTAssertEqual(m.latex, "\\int x\\,dx")
    }

    func testBracketMathBlockUnclosed() {
        let blocks = Golden.lex("\\[\n\\frac a b")
        guard case .mathBlock(let m) = blocks[0] else {
            return XCTFail("expected math block")
        }
        XCTAssertFalse(m.isClosed)
    }

    func testRawHTMLBlockCapture() {
        let blocks = Golden.lex("<div class=\"x\">\n<p>hi</p>\n</div>")
        XCTAssertEqual(blocks.count, 1)
        guard case .htmlBlock(let html) = blocks[0] else {
            return XCTFail("expected html block, got \(blocks[0])")
        }
        XCTAssertEqual(html.raw, "<div class=\"x\">\n<p>hi</p>\n</div>")
    }

    func testHTMLBlockEndsAtBlankLine() {
        let blocks = Golden.lex("<table>\n</table>\n\nparagraph")
        XCTAssertEqual(blocks.count, 2)
        guard case .htmlBlock(let html) = blocks[0] else {
            return XCTFail("expected html block")
        }
        XCTAssertEqual(html.raw, "<table>\n</table>")
        XCTAssertEqual(Golden.paragraphText(blocks[1]), "paragraph")
    }
}
