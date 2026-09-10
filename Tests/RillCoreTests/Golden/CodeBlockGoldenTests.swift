import XCTest
@testable import RillCore

/// Golden tests for fenced and indented code blocks.
final class CodeBlockGoldenTests: XCTestCase {
    func testFencedBacktickClosed() {
        let blocks = Golden.lex("```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let cb) = blocks[0] else {
            return XCTFail("expected code block")
        }
        XCTAssertEqual(cb.language, "swift")
        XCTAssertEqual(cb.content, "let x = 1\n")
        XCTAssertTrue(cb.isClosed)
    }

    func testFencedBacktickUnclosed() {
        let blocks = Golden.lex("```\nstill typing")
        guard case .codeBlock(let cb) = blocks[0] else {
            return XCTFail("expected code block")
        }
        XCTAssertNil(cb.language)
        XCTAssertEqual(cb.content, "still typing\n")
        XCTAssertFalse(cb.isClosed)
    }

    func testFencedTildeClosed() {
        let blocks = Golden.lex("~~~\nplain\n~~~")
        guard case .codeBlock(let cb) = blocks[0] else {
            return XCTFail("expected code block")
        }
        XCTAssertEqual(cb.content, "plain\n")
        XCTAssertTrue(cb.isClosed)
    }

    func testBacktickFenceNotClosedByTilde() {
        let blocks = Golden.lex("```\ncode\n~~~\nmore\n```")
        guard case .codeBlock(let cb) = blocks[0] else {
            return XCTFail("expected code block")
        }
        XCTAssertEqual(cb.content, "code\n~~~\nmore\n")
        XCTAssertTrue(cb.isClosed)
    }

    func testIndentedCodeBlock() {
        let blocks = Golden.lex("    indented one\n    indented two")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let cb) = blocks[0] else {
            return XCTFail("expected code block, got \(blocks[0])")
        }
        XCTAssertNil(cb.language)
        XCTAssertEqual(cb.content, "indented one\nindented two\n")
        XCTAssertTrue(cb.isClosed)
    }

    func testIndentedCodePreservesInteriorBlankLines() {
        let blocks = Golden.lex("    a\n\n    b")
        guard case .codeBlock(let cb) = blocks[0] else {
            return XCTFail("expected code block")
        }
        XCTAssertEqual(cb.content, "a\n\nb\n")
    }
}
