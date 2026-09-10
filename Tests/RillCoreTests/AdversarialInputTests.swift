import XCTest
@testable import RillCore

/// Robustness tests: malformed or adversarial input must never crash or hang the
/// parser, end-to-end through the streaming entry points.
final class AdversarialInputTests: XCTestCase {

    /// A long single-line chain of footnote-definition markers (`[^a]: [^b]: …`)
    /// must not recurse without bound and overflow the stack.
    func testDeepFootnoteChainDoesNotStackOverflow() {
        let source = String(repeating: "[^a]: ", count: 5_000)
        // Must return a Document without crashing (depth is capped).
        let doc = BlockLexer.lex(Array(source.utf8)[...])
        XCTAssertFalse(doc.isEmpty)
    }

    /// The same chain fed through the incremental streaming parser (where the
    /// unterminated line stays in the open tail and is re-lexed on every delta)
    /// must also stay bounded.
    func testDeepFootnoteChainStreamsWithoutCrash() {
        let parser = IncrementalParser()
        let unit = "[^a]: "
        var offset = 0
        for _ in 0..<400 {
            parser.consume(delta: unit, at: offset)
            offset += unit.utf8.count
        }
        XCTAssertFalse(parser.document.blocks.isEmpty)
    }

    /// A long run of unmatched opening brackets must parse in linear time (the
    /// per-bracket label scan is bounded), not quadratic — i.e. it completes
    /// quickly instead of hanging.
    func testUnmatchedBracketRunDoesNotHang() {
        let source = String(repeating: "[", count: 15_000)
        let blocks = BlockLexer.lex(Array(source.utf8)[...])
        let resolved = InlineParser.resolveInlines(in: blocks, config: .default)
        XCTAssertFalse(resolved.isEmpty)
    }

    /// A run of unmatched image-opens (`![`) is likewise bounded.
    func testUnmatchedImageOpenRunDoesNotHang() {
        let source = String(repeating: "![", count: 15_000)
        let blocks = BlockLexer.lex(Array(source.utf8)[...])
        let resolved = InlineParser.resolveInlines(in: blocks, config: .default)
        XCTAssertFalse(resolved.isEmpty)
    }

    /// Degenerate inputs (empty, whitespace, lone control characters) parse to a
    /// well-formed Document without crashing.
    func testDegenerateInputs() {
        for source in ["", " ", "\n\n\n", "\t", "\r\n", String(repeating: " ", count: 10_000)] {
            let doc = BlockLexer.lex(Array(source.utf8)[...])
            _ = Document(blocks: InlineParser.resolveInlines(in: doc, config: .default))
        }
    }
}
