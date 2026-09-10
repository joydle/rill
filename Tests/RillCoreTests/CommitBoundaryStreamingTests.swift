import XCTest
@testable import RillCore

/// Streaming-equivalence regression tests for commit-boundary edge cases where a
/// list sits at a blank line near the end of the buffer. A premature commit at
/// such a blank freezes a prefix that a later delta can no longer extend (a loose
/// sibling item or a shallow-indented continuation), diverging from the one-shot
/// parse. Each case must yield the same ``Document`` one-shot and streamed.
final class CommitBoundaryStreamingTests: XCTestCase {

    private func oneShot(_ source: String) -> Document {
        let blocks = BlockLexer.lex(Array(source.utf8)[...])
        return Document(blocks: InlineParser.resolveInlines(in: blocks, config: .default))
    }

    /// Feeds the source one UTF-8 byte at a time as append-deltas.
    private func streamedByByte(_ source: String) -> Document {
        let parser = IncrementalParser()
        let bytes = Array(source.utf8)
        var legal = Set<Int>([0, bytes.count])
        var idx = 0
        for scalar in source.unicodeScalars {
            idx += String(scalar).utf8.count
            legal.insert(idx)
        }
        let cuts = legal.sorted()
        var offset = 0
        for i in 1..<cuts.count {
            let chunk = String(decoding: bytes[cuts[i - 1]..<cuts[i]], as: UTF8.self)
            parser.consume(delta: chunk, at: offset)
            offset += chunk.utf8.count
        }
        return parser.document
    }

    /// Feeds the source as growing snapshots, one scalar at a time.
    private func streamedBySnapshot(_ source: String) -> Document {
        let parser = IncrementalParser()
        var acc = ""
        for scalar in source.unicodeScalars {
            acc.unicodeScalars.append(scalar)
            parser.consume(snapshot: acc)
        }
        if acc.isEmpty { parser.consume(snapshot: acc) }
        return parser.document
    }

    private func assertEquivalent(_ source: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = oneShot(source)
        XCTAssertEqual(streamedByByte(source), expected, "byte-delta: \(message)", file: file, line: line)
        XCTAssertEqual(streamedBySnapshot(source), expected, "snapshot: \(message)", file: file, line: line)
    }

    func testLooseListContinuationShallowIndent() {
        assertEquivalent("- a\n\n  continued", "shallow-indented continuation attaches to the list item")
    }

    func testLooseListContinuationShallowIndentTrailingNewline() {
        assertEquivalent("- a\n\n  continued\n", "shallow-indented continuation with trailing newline")
    }

    func testParagraphThenListThenBlankAtEnd() {
        assertEquivalent("é\n- [x] <\r\n\n- [x] [1][", "list between paragraph and trailing blank keeps loose sibling")
    }

    func testNestedTaskListContinuationAfterBlank() {
        assertEquivalent("\\__![\n- - [ ] \r\n\n    - [ ] \r\n", "indented continuation stays a nested list item")
    }

    func testOrderedLooseListSplitDuringStream() {
        assertEquivalent("1. one\n\n1. two", "ordered loose list is one list, not two")
    }
}
