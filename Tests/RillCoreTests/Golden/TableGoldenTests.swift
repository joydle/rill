import XCTest
@testable import RillCore

/// Golden tests for GFM pipe tables and column alignment.
final class TableGoldenTests: XCTestCase {
    func testSimpleTable() {
        let src = """
        | Name | Age |
        | --- | --- |
        | Alice | 30 |
        | Bob | 25 |
        """
        let blocks = Golden.lex(src)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("expected table, got \(blocks[0])")
        }
        XCTAssertEqual(table.header.count, 2)
        XCTAssertEqual(Golden.rawText(table.header[0]), "Name")
        XCTAssertEqual(Golden.rawText(table.header[1]), "Age")
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(Golden.rawText(table.rows[0][0]), "Alice")
        XCTAssertEqual(Golden.rawText(table.rows[1][1]), "25")
    }

    func testAlignmentParsing() {
        let src = """
        | L | C | R | D |
        | :--- | :---: | ---: | --- |
        | 1 | 2 | 3 | 4 |
        """
        let blocks = Golden.lex(src)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("expected table")
        }
        XCTAssertEqual(table.alignments, [.left, .center, .right, .none])
    }

    func testTableEndsAtNonTableLine() {
        let src = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        after the table
        """
        let blocks = Golden.lex(src)
        XCTAssertEqual(blocks.count, 2)
        guard case .table = blocks[0] else {
            return XCTFail("expected table first")
        }
        XCTAssertEqual(Golden.paragraphText(blocks[1]), "after the table")
    }

    func testHeaderOnlyTable() {
        let src = """
        | H1 | H2 |
        | --- | --- |
        """
        let blocks = Golden.lex(src)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("expected table")
        }
        XCTAssertEqual(table.rows.count, 0)
        XCTAssertEqual(table.header.count, 2)
    }
}
