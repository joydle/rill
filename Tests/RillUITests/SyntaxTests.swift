import XCTest
import SwiftUI
@testable import RillUI

/// Tests for RillUI syntax highlighting: the ``CodeHighlighter`` protocol and
/// the default ``RillSyntax`` highlighter.
///
/// These run headlessly. They assert on the runs of the produced
/// `AttributedString` — specifically that a token is colored with the matching
/// slot of the theme's syntax palette (a keyword run gets the keyword color, a
/// quoted string gets the string color, a `//` comment gets the comment color,
/// a numeric literal gets the number color). There are no pixel snapshots.
@MainActor
final class SyntaxTests: XCTestCase {

    private let theme = RillTheme.default
    private var palette: RillTheme.SyntaxColors { theme.colors.syntax }

    // MARK: - Helpers

    /// The highlighter under test.
    private func makeHighlighter() -> RillSyntax {
        RillSyntax(theme: theme)
    }

    /// Returns the first run whose substring exactly contains `needle`, along
    /// with its foreground color.
    private func color(
        of needle: String,
        in attributed: AttributedString
    ) -> Color? {
        for run in attributed.runs {
            let segment = String(attributed[run.range].characters)
            if segment.contains(needle) {
                return run.foregroundColor
            }
        }
        return nil
    }

    /// Asserts that the round-tripped plain text of the highlight is unchanged —
    /// highlighting only adds attributes, never mutates characters.
    private func assertTextPreserved(
        _ code: String,
        _ attributed: AttributedString,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(attributed.characters), code,
                       "Highlighting must preserve the source text verbatim.",
                       file: file, line: line)
    }

    // MARK: - Swift

    /// The Swift keyword `func` is colored with the theme's keyword color.
    func testSwiftKeywordFuncIsColoredAsKeyword() {
        let highlighter = makeHighlighter()
        let code = "func greet() {}"
        let result = highlighter.highlight(code, language: "swift")
        assertTextPreserved(code, result)
        XCTAssertEqual(color(of: "func", in: result), palette.keyword,
                       "`func` must be colored as a keyword.")
        // The identifier `greet` is not a keyword and must not get keyword color.
        XCTAssertNotEqual(color(of: "greet", in: result), palette.keyword,
                          "A plain identifier must not be colored as a keyword.")
    }

    /// A double-quoted string literal is colored with the theme's string color.
    func testSwiftStringRunIsColoredAsString() {
        let highlighter = makeHighlighter()
        let code = "let name = \"Rill\""
        let result = highlighter.highlight(code, language: "swift")
        assertTextPreserved(code, result)
        XCTAssertEqual(color(of: "Rill", in: result), palette.string,
                       "A quoted string run must be colored as a string.")
        XCTAssertEqual(color(of: "let", in: result), palette.keyword,
                       "`let` must be colored as a keyword.")
    }

    /// A `//` line comment is colored with the theme's comment color.
    func testSwiftLineCommentIsColoredAsComment() {
        let highlighter = makeHighlighter()
        let code = "let x = 1 // note here"
        let result = highlighter.highlight(code, language: "swift")
        assertTextPreserved(code, result)
        XCTAssertEqual(color(of: "note here", in: result), palette.comment,
                       "A `//` comment run must be colored as a comment.")
    }

    /// A `/* ... */` block comment is colored with the theme's comment color.
    func testSwiftBlockCommentIsColoredAsComment() {
        let highlighter = makeHighlighter()
        let code = "let x = /* inline */ 1"
        let result = highlighter.highlight(code, language: "swift")
        assertTextPreserved(code, result)
        XCTAssertEqual(color(of: "inline", in: result), palette.comment,
                       "A `/* */` block comment run must be colored as a comment.")
    }

    /// A numeric literal is colored with the theme's number color.
    func testSwiftNumberIsColoredAsNumber() {
        let highlighter = makeHighlighter()
        let code = "let x = 42"
        let result = highlighter.highlight(code, language: "swift")
        assertTextPreserved(code, result)
        XCTAssertEqual(color(of: "42", in: result), palette.number,
                       "A numeric literal must be colored as a number.")
    }

    /// The whole highlight uses the theme's monospaced code font.
    func testHighlightUsesCodeFont() {
        let highlighter = makeHighlighter()
        let result = highlighter.highlight("func f() {}", language: "swift")
        let funcRun = result.runs.first { run in
            String(result[run.range].characters).contains("func")
        }
        XCTAssertEqual(funcRun?.font, theme.fonts.code,
                       "Every run must carry the theme's code font.")
    }

    // MARK: - JavaScript / TypeScript

    func testJavaScriptKeywordIsColoredAsKeyword() {
        let highlighter = makeHighlighter()
        let code = "const x = 1;"
        let result = highlighter.highlight(code, language: "javascript")
        XCTAssertEqual(color(of: "const", in: result), palette.keyword,
                       "`const` must be colored as a keyword in JavaScript.")
        XCTAssertEqual(color(of: "1", in: result), palette.number)
    }

    func testTypeScriptKeywordIsColoredAsKeyword() {
        let highlighter = makeHighlighter()
        let code = "interface Foo {}"
        let result = highlighter.highlight(code, language: "ts")
        XCTAssertEqual(color(of: "interface", in: result), palette.keyword,
                       "`interface` must be colored as a keyword in TypeScript.")
    }

    func testJavaScriptStringAndComment() {
        let highlighter = makeHighlighter()
        let code = "let s = 'hi'; // tail"
        let result = highlighter.highlight(code, language: "js")
        XCTAssertEqual(color(of: "hi", in: result), palette.string,
                       "A single-quoted JS string must be colored as a string.")
        XCTAssertEqual(color(of: "tail", in: result), palette.comment)
    }

    // MARK: - Python

    func testPythonKeywordAndHashComment() {
        let highlighter = makeHighlighter()
        let code = "def f(): # body\n    return 3"
        let result = highlighter.highlight(code, language: "python")
        XCTAssertEqual(color(of: "def", in: result), palette.keyword,
                       "`def` must be colored as a keyword in Python.")
        XCTAssertEqual(color(of: "body", in: result), palette.comment,
                       "A `#` comment must be colored as a comment in Python.")
        XCTAssertEqual(color(of: "return", in: result), palette.keyword)
        XCTAssertEqual(color(of: "3", in: result), palette.number)
    }

    // MARK: - JSON

    func testJSONStringAndNumber() {
        let highlighter = makeHighlighter()
        let code = "{\"key\": 12, \"on\": true}"
        let result = highlighter.highlight(code, language: "json")
        XCTAssertEqual(color(of: "key", in: result), palette.string,
                       "A JSON string must be colored as a string.")
        XCTAssertEqual(color(of: "12", in: result), palette.number,
                       "A JSON number must be colored as a number.")
        XCTAssertEqual(color(of: "true", in: result), palette.keyword,
                       "A JSON literal `true` must be colored as a keyword.")
    }

    // MARK: - Bash

    func testBashKeywordAndHashComment() {
        let highlighter = makeHighlighter()
        let code = "if true; then # go\necho 1\nfi"
        let result = highlighter.highlight(code, language: "bash")
        XCTAssertEqual(color(of: "if", in: result), palette.keyword,
                       "`if` must be colored as a keyword in Bash.")
        XCTAssertEqual(color(of: "go", in: result), palette.comment,
                       "A `#` comment must be colored as a comment in Bash.")
    }

    // MARK: - HTML

    func testHTMLTagAndComment() {
        let highlighter = makeHighlighter()
        let code = "<div> <!-- note --> text </div>"
        let result = highlighter.highlight(code, language: "html")
        XCTAssertEqual(color(of: "note", in: result), palette.comment,
                       "An HTML `<!-- -->` comment must be colored as a comment.")
        // The tag name should be colored as a keyword (tag).
        XCTAssertEqual(color(of: "div", in: result), palette.keyword,
                       "An HTML tag name must be colored as a keyword.")
    }

    // MARK: - Rust

    func testRustKeywordStringComment() {
        let highlighter = makeHighlighter()
        let code = "fn main() { let s = \"hi\"; // done\n}"
        let result = highlighter.highlight(code, language: "rust")
        XCTAssertEqual(color(of: "fn", in: result), palette.keyword,
                       "`fn` must be colored as a keyword in Rust.")
        XCTAssertEqual(color(of: "hi", in: result), palette.string)
        XCTAssertEqual(color(of: "done", in: result), palette.comment)
        XCTAssertEqual(color(of: "let", in: result), palette.keyword)
    }

    // MARK: - Generic fallback (unknown language)

    /// An unknown language uses the generic tokenizer: it still colors strings,
    /// numbers, and `//`/`#` comments, but applies no language-specific keyword
    /// set.
    func testUnknownLanguageUsesGenericTokenizer() {
        let highlighter = makeHighlighter()
        let code = "value = \"hi\" 7 // c"
        let result = highlighter.highlight(code, language: "cobol-from-mars")
        assertTextPreserved(code, result)
        XCTAssertEqual(color(of: "hi", in: result), palette.string,
                       "The generic tokenizer must still color strings.")
        XCTAssertEqual(color(of: "7", in: result), palette.number,
                       "The generic tokenizer must still color numbers.")
        XCTAssertEqual(color(of: "c", in: result), palette.comment,
                       "The generic tokenizer must still color `//` comments.")
        // `value` is an identifier; the generic tokenizer has no Swift keywords,
        // so a Swift-only keyword like `func` would NOT be colored here.
        let funcLike = highlighter.highlight("func x", language: "cobol-from-mars")
        XCTAssertNotEqual(color(of: "func", in: funcLike), palette.keyword,
                          "The generic tokenizer must not apply Swift keyword coloring.")
    }

    /// A nil language also routes to the generic tokenizer.
    func testNilLanguageUsesGenericTokenizer() {
        let highlighter = makeHighlighter()
        let code = "x = \"hi\""
        let result = highlighter.highlight(code, language: nil)
        XCTAssertEqual(color(of: "hi", in: result), palette.string)
    }

    // MARK: - Caching

    /// Repeated highlights of the same code+language return an equal result and
    /// reuse the cache.
    func testCachingReturnsEqualResultAndRecordsHit() {
        let highlighter = makeHighlighter()
        let code = "func f() { let x = 1 }"
        let first = highlighter.highlight(code, language: "swift")
        let second = highlighter.highlight(code, language: "swift")
        XCTAssertEqual(String(first.characters), String(second.characters))
        XCTAssertEqual(color(of: "func", in: first), color(of: "func", in: second))
        XCTAssertGreaterThanOrEqual(highlighter.cacheHitCount, 1,
                                    "A second identical highlight must hit the cache.")
    }

    /// Different languages for the same code are cached independently and may
    /// color the same token differently.
    func testCacheKeyIncludesLanguage() {
        let highlighter = makeHighlighter()
        // `interface` is a TS keyword but not a Swift keyword.
        let asSwift = highlighter.highlight("interface", language: "swift")
        let asTS = highlighter.highlight("interface", language: "typescript")
        XCTAssertNotEqual(color(of: "interface", in: asSwift), palette.keyword,
                          "`interface` is not a Swift keyword.")
        XCTAssertEqual(color(of: "interface", in: asTS), palette.keyword,
                       "`interface` is a TypeScript keyword.")
    }

    // MARK: - Theme palette

    /// The default theme exposes a fully-populated syntax palette so highlighting
    /// works with zero configuration.
    func testDefaultThemeSyntaxPaletteIsPopulated() {
        let p = RillTheme.default.colors.syntax
        // Reading each slot must not trap; slots are distinct enough to classify.
        _ = p.keyword
        _ = p.string
        _ = p.comment
        _ = p.number
        _ = p.plain
        // The plain color falls back to the primary text color.
        XCTAssertEqual(p.plain, RillTheme.default.colors.textPrimary)
    }
}
