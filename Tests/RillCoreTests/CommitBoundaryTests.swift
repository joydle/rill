import XCTest
@testable import RillCore

/// Verifies the incremental engine's commit discipline: an open construct (an
/// unterminated code fence, an open math block, a trailing paragraph, or an open
/// table) is NEVER frozen into the committed prefix, and `commitIndex` advances
/// exactly when — and only when — a block definitively closes.
final class CommitBoundaryTests: XCTestCase {

    /// Drives a parser through a sequence of append-deltas, returning the parser
    /// after the final delta so its `commitIndex`/`document` can be inspected.
    private func stream(_ pieces: [String]) -> IncrementalParser {
        let parser = IncrementalParser()
        var offset = 0
        for piece in pieces {
            parser.consume(delta: piece, at: offset)
            offset += piece.utf8.count
        }
        return parser
    }

    /// An open fence keeps its content out of the committed prefix.
    func testOpenFenceNeverCommitted() {
        let parser = stream(["```swift\n", "let x = 1\n", "more code\n"])
        // Nothing has closed; the fence is the live tail.
        XCTAssertEqual(parser.commitIndex, 0, "open fence must not commit")
        // The open fence is present in the document, marked not closed.
        guard case .codeBlock(let cb)? = parser.document.blocks.last else {
            return XCTFail("expected an open code block in the tail")
        }
        XCTAssertFalse(cb.isClosed)
    }

    /// Closing the fence advances `commitIndex` past the whole block.
    func testFenceCommitsOnClose() {
        let beforeClose = stream(["```swift\n", "let x = 1\n"])
        XCTAssertEqual(beforeClose.commitIndex, 0)

        let afterClose = stream(["```swift\n", "let x = 1\n", "```\n"])
        let closedBytes = "```swift\nlet x = 1\n```\n".utf8.count
        XCTAssertEqual(afterClose.commitIndex, closedBytes,
                       "commitIndex must advance past the closed fence")
    }

    /// An open `$$` math block is never committed until its closing delimiter.
    func testOpenMathNeverCommitted() {
        let open = stream(["$$\n", "E = mc^2\n"])
        XCTAssertEqual(open.commitIndex, 0, "open math must not commit")

        let closed = stream(["$$\n", "E = mc^2\n", "$$\n"])
        let bytes = "$$\nE = mc^2\n$$\n".utf8.count
        XCTAssertEqual(closed.commitIndex, bytes, "math commits exactly on close")
    }

    /// A trailing paragraph (no closing blank line) stays open: a future line
    /// could extend it via lazy continuation, so it is never committed.
    func testTrailingParagraphNeverCommitted() {
        let parser = stream(["A paragraph line\n", "still going\n"])
        XCTAssertEqual(parser.commitIndex, 0,
                       "an unterminated trailing paragraph must stay in the tail")
    }

    /// A paragraph closed by a blank line commits exactly through that blank line.
    func testParagraphCommitsAfterBlankLine() {
        let parser = stream(["First para.\n", "\n", "Second para.\n"])
        let committedBytes = "First para.\n\n".utf8.count
        XCTAssertEqual(parser.commitIndex, committedBytes,
                       "paragraph commits through its closing blank line")
        // The second paragraph remains open in the tail.
        XCTAssertGreaterThan(parser.document.blocks.count, 1)
    }

    /// An open table (header + rows, no closing blank line) is not committed,
    /// because a future line could add another row.
    func testOpenTableNeverCommitted() {
        let parser = stream(["| a | b |\n", "|---|---|\n", "| 1 | 2 |\n"])
        XCTAssertEqual(parser.commitIndex, 0, "open table must stay in the tail")
        guard case .table? = parser.document.blocks.last else {
            return XCTFail("expected a table in the tail")
        }
    }

    /// A table closed by a following blank line commits through that blank line.
    func testTableCommitsAfterBlankLine() {
        let parser = stream(["| a | b |\n", "|---|---|\n", "| 1 | 2 |\n", "\n"])
        let bytes = "| a | b |\n|---|---|\n| 1 | 2 |\n\n".utf8.count
        XCTAssertEqual(parser.commitIndex, bytes, "table commits on closing blank line")
    }

    /// A heading is single-line and immediately closable: it commits as soon as
    /// its terminating newline arrives.
    func testHeadingCommitsImmediately() {
        let parser = stream(["# Title\n"])
        XCTAssertEqual(parser.commitIndex, "# Title\n".utf8.count,
                       "a terminated heading commits immediately")
    }

    /// `commitIndex` is monotonically non-decreasing across an append-only stream.
    func testCommitIndexMonotonic() {
        let parser = IncrementalParser()
        let doc = "# H\n\nPara.\n\n```\ncode\n```\n\nTail paragraph\n"
        let bytes = Array(doc.utf8)
        var offset = 0
        var last = 0
        // Feed two bytes at a time.
        while offset < bytes.count {
            let end = min(offset + 2, bytes.count)
            parser.consume(delta: String(decoding: bytes[offset..<end], as: UTF8.self), at: offset)
            XCTAssertGreaterThanOrEqual(parser.commitIndex, last,
                                        "commitIndex must never regress")
            last = parser.commitIndex
            offset = end
        }
    }
}
