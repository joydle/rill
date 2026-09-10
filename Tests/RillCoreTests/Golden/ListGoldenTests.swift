import XCTest
@testable import RillCore

/// Golden tests for ordered/unordered lists, nesting, tight/loose, and GFM task items.
final class ListGoldenTests: XCTestCase {
    func testUnorderedTightList() {
        let blocks = Golden.lex("- a\n- b\n- c")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let list) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertFalse(list.isOrdered)
        XCTAssertTrue(list.isTight)
        XCTAssertEqual(list.items.count, 3)
        XCTAssertEqual(Golden.paragraphText(list.items[0].blocks[0]), "a")
        XCTAssertEqual(Golden.paragraphText(list.items[2].blocks[0]), "c")
    }

    func testOrderedListWithStart() {
        let blocks = Golden.lex("3. third\n4. fourth")
        guard case .list(let list) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertTrue(list.isOrdered)
        XCTAssertEqual(list.start, 3)
        XCTAssertEqual(list.items.count, 2)
    }

    func testLooseListDetectedFromBlankLineBetweenItems() {
        let blocks = Golden.lex("- a\n\n- b")
        guard case .list(let list) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertFalse(list.isTight)
        XCTAssertEqual(list.items.count, 2)
    }

    func testNestedList() {
        let blocks = Golden.lex("- outer\n  - inner")
        guard case .list(let list) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertEqual(list.items.count, 1)
        let nested = list.items[0].blocks.compactMap { block -> List? in
            if case .list(let l) = block { return l }
            return nil
        }
        XCTAssertEqual(nested.count, 1)
        XCTAssertEqual(Golden.paragraphText(nested[0].items[0].blocks[0]), "inner")
    }

    func testTaskListUncheckedAndChecked() {
        let blocks = Golden.lex("- [ ] todo\n- [x] done")
        guard case .list(let list) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].checkbox, false)
        XCTAssertEqual(list.items[1].checkbox, true)
        XCTAssertEqual(Golden.paragraphText(list.items[0].blocks[0]), "todo")
        XCTAssertEqual(Golden.paragraphText(list.items[1].blocks[0]), "done")
    }

    func testPlainItemHasNilCheckbox() {
        let blocks = Golden.lex("- plain")
        guard case .list(let list) = blocks[0] else {
            return XCTFail("expected list")
        }
        XCTAssertNil(list.items[0].checkbox)
    }
}
