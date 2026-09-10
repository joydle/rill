import XCTest
@testable import RillCore

/// Structural tests for ``LineScanner`` and ``BlockLexer`` beyond the per-construct
/// golden cases.
final class BlockLexerTests: XCTestCase {
    func testLineScannerSplitsOnNewlines() {
        let bytes = Array("a\nbb\n\nc".utf8)
        var scanner = LineScanner(bytes[...])
        var lines: [String] = []
        while let line = scanner.next() {
            lines.append(String(decoding: line.bytes, as: UTF8.self))
        }
        XCTAssertEqual(lines, ["a", "bb", "", "c"])
    }

    func testLineScannerReportsByteRanges() {
        let bytes = Array("ab\ncd".utf8)
        var scanner = LineScanner(bytes[...])
        let first = scanner.next()
        let second = scanner.next()
        XCTAssertEqual(first?.range, 0..<2)   // "ab", excludes the newline
        XCTAssertEqual(first?.terminatedByNewline, true)
        XCTAssertEqual(second?.range, 3..<5)  // "cd"
        XCTAssertEqual(second?.terminatedByNewline, false)
    }

    func testEmptyInputYieldsNoBlocks() {
        XCTAssertTrue(Golden.lex("").isEmpty)
        XCTAssertTrue(Golden.lex("\n\n\n").isEmpty)
    }

    func testMixedDocumentOrder() {
        let src = """
        # Heading

        A paragraph.

        - item one
        - item two

        ```
        code
        ```
        """
        let blocks = Golden.lex(src)
        XCTAssertEqual(blocks.count, 4)
        guard case .heading = blocks[0] else { return XCTFail("0 heading") }
        guard case .paragraph = blocks[1] else { return XCTFail("1 paragraph") }
        guard case .list = blocks[2] else { return XCTFail("2 list") }
        guard case .codeBlock = blocks[3] else { return XCTFail("3 code") }
    }

    func testLexAcceptsArraySlice() {
        let bytes = Array("xx# Heading".utf8)
        // Slice past the leading "xx" so the slice's startIndex != 0.
        let slice = bytes[2...]
        let blocks = BlockLexer.lex(slice)
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let h) = blocks[0] else { return XCTFail("expected heading") }
        XCTAssertEqual(h.level, 1)
    }
}
