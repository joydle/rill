import XCTest
@testable import RillCore

/// Golden tests for ATX headings, paragraphs, and blank-line separation.
final class HeadingsAndParagraphsGoldenTests: XCTestCase {
    func testATXHeadingsAllLevels() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let blocks = Golden.lex("\(hashes) Title \(level)")
            XCTAssertEqual(blocks.count, 1)
            guard case .heading(let h) = blocks[0] else {
                return XCTFail("expected heading, got \(blocks[0])")
            }
            XCTAssertEqual(h.level, level)
            XCTAssertEqual(Golden.rawText(h.inlines), "Title \(level)")
        }
    }

    func testSevenHashesIsParagraphNotHeading() {
        let blocks = Golden.lex("####### Too deep")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(Golden.paragraphText(blocks[0]), "####### Too deep")
    }

    func testHeadingRequiresSpaceAfterHashes() {
        let blocks = Golden.lex("#NotAHeading")
        XCTAssertEqual(Golden.paragraphText(blocks.first ?? .thematicBreak), "#NotAHeading")
    }

    func testATXHeadingTrailingHashesStripped() {
        let blocks = Golden.lex("## Title ##")
        guard case .heading(let h) = blocks[0] else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(h.level, 2)
        XCTAssertEqual(Golden.rawText(h.inlines), "Title")
    }

    func testParagraphMultilineJoined() {
        let blocks = Golden.lex("line one\nline two")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(Golden.paragraphText(blocks[0]), "line one\nline two")
    }

    func testBlankLineSeparatesParagraphs() {
        let blocks = Golden.lex("first para\n\nsecond para")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(Golden.paragraphText(blocks[0]), "first para")
        XCTAssertEqual(Golden.paragraphText(blocks[1]), "second para")
    }

    func testLeadingAndTrailingBlankLinesIgnored() {
        let blocks = Golden.lex("\n\n  hello  \n\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(Golden.paragraphText(blocks[0]), "hello")
    }
}
