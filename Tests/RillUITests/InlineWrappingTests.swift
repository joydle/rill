import XCTest
import Foundation
@testable import RillUI

/// Regression tests for inline word-splitting, which lets the mixed-content flow
/// layout (text interleaved with citation pills / inline math / images) wrap
/// between words instead of treating each text span as one atomic, overflowing
/// child. See `RichInlineText.splitWords`.
final class InlineWrappingTests: XCTestCase {

    func testSplitWordsBreaksOnSpacesAndIsLossless() {
        let input = AttributedString("Rill renders markdown")
        let words = RichInlineText.splitWords(input)

        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(String(words[0].characters), "Rill ")
        XCTAssertEqual(String(words[1].characters), "renders ")
        XCTAssertEqual(String(words[2].characters), "markdown")

        // Reassembling the words reproduces the original text exactly.
        var joined = AttributedString()
        for word in words { joined.append(word) }
        XCTAssertEqual(String(joined.characters), "Rill renders markdown")
    }

    func testSplitWordsPreservesRunAttributes() {
        var input = AttributedString("normal ")
        var bold = AttributedString("bold")
        bold.inlinePresentationIntent = .stronglyEmphasized
        input.append(bold)

        let words = RichInlineText.splitWords(input)

        XCTAssertEqual(words.count, 2)
        XCTAssertNil(words[0].runs.first?.inlinePresentationIntent)
        XCTAssertEqual(words[1].runs.first?.inlinePresentationIntent, .stronglyEmphasized)
    }

    func testSplitWordsHandlesEmptyAndWhitespace() {
        XCTAssertTrue(RichInlineText.splitWords(AttributedString("")).isEmpty)

        let spaced = RichInlineText.splitWords(AttributedString("a  b"))
        // "a", " " (the second space becomes its own chunk), "b".
        XCTAssertEqual(spaced.map { String($0.characters) }, ["a ", " ", "b"])
    }
}
