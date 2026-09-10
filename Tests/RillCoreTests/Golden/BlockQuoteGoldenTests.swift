import XCTest
@testable import RillCore

/// Golden tests for block quotes, including nesting.
final class BlockQuoteGoldenTests: XCTestCase {
    func testSimpleBlockQuote() {
        let blocks = Golden.lex("> quoted text")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockQuote(let bq) = blocks[0] else {
            return XCTFail("expected block quote")
        }
        XCTAssertEqual(bq.blocks.count, 1)
        XCTAssertEqual(Golden.paragraphText(bq.blocks[0]), "quoted text")
    }

    func testBlockQuoteMultiLineParagraph() {
        let blocks = Golden.lex("> line one\n> line two")
        guard case .blockQuote(let bq) = blocks[0] else {
            return XCTFail("expected block quote")
        }
        XCTAssertEqual(bq.blocks.count, 1)
        XCTAssertEqual(Golden.paragraphText(bq.blocks[0]), "line one\nline two")
    }

    func testNestedBlockQuote() {
        let blocks = Golden.lex("> outer\n> > inner")
        guard case .blockQuote(let outer) = blocks[0] else {
            return XCTFail("expected outer block quote")
        }
        // outer contains a paragraph and a nested block quote.
        let nested = outer.blocks.compactMap { block -> BlockQuote? in
            if case .blockQuote(let q) = block { return q }
            return nil
        }
        XCTAssertEqual(nested.count, 1)
        XCTAssertEqual(Golden.paragraphText(nested[0].blocks[0]), "inner")
    }

    func testBlockQuoteContainsHeading() {
        let blocks = Golden.lex("> # Quoted Heading")
        guard case .blockQuote(let bq) = blocks[0] else {
            return XCTFail("expected block quote")
        }
        guard case .heading(let h) = bq.blocks[0] else {
            return XCTFail("expected heading inside quote")
        }
        XCTAssertEqual(h.level, 1)
        XCTAssertEqual(Golden.rawText(h.inlines), "Quoted Heading")
    }
}
