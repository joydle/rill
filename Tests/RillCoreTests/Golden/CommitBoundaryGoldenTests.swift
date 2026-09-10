import XCTest
@testable import RillCore

/// Golden tests for ``CommitBoundary/lastClosedIndex(in:)``.
///
/// The returned offset is the byte index just past the last definitively-closed
/// block: everything before it can never change as more text streams in.
final class CommitBoundaryGoldenTests: XCTestCase {
    private func boundary(_ source: String) -> Int {
        let bytes = Array(source.utf8)
        return CommitBoundary.lastClosedIndex(in: bytes[...])
    }

    func testParagraphClosedByBlankLineCommits() {
        // "p\n\n" — paragraph is closed by the blank line; the trailing tail is empty.
        let src = "para\n\n"
        XCTAssertEqual(boundary(src), Array(src.utf8).count)
    }

    func testTrailingOpenParagraphNotCommitted() {
        // The final paragraph could still be extended → not committed.
        let src = "closed\n\nstill open"
        let idx = boundary(src)
        XCTAssertEqual(idx, Array("closed\n\n".utf8).count)
    }

    func testOpenFenceNeverCommits() {
        let src = "```\ncode line\nmore"
        XCTAssertEqual(boundary(src), 0)
    }

    func testClosedFenceCommits() {
        let src = "```\ncode\n```\n"
        XCTAssertEqual(boundary(src), Array(src.utf8).count)
    }

    func testOpenMathBlockNeverCommits() {
        let src = "$$\nx = 1\n"
        XCTAssertEqual(boundary(src), 0)
    }

    func testHeadingCommitsImmediately() {
        // A heading is single-line and closes at its newline.
        let src = "# Title\n"
        XCTAssertEqual(boundary(src), Array(src.utf8).count)
    }

    func testHeadingWithoutTrailingNewlineNotCommitted() {
        // Without a newline the heading line is still the open tail.
        let src = "# Title"
        XCTAssertEqual(boundary(src), 0)
    }

    func testThematicBreakCommits() {
        let src = "---\n"
        XCTAssertEqual(boundary(src), Array(src.utf8).count)
    }
}
