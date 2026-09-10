import SwiftUI
import RillUI

/// A single visual-QA case: a title plus a Markdown snippet that exercises one
/// rendering surface (or a tricky combination), so it can be rendered full-screen
/// and screenshotted for inspection.
public struct QACase: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let markdown: String
}

/// A comprehensive catalog of Markdown rendering cases used for systematic visual
/// QA. Each case renders on its own screen (selected by the `RILL_QA_CASE`
/// environment variable) so a screenshot can be captured and inspected for
/// overflow, clipping, collisions, spacing, and alignment defects.
public enum QACatalog {
    public static let cases: [QACase] = {
        let raw: [(String, String)] = [
            ("Inline math in a sentence",
             "The Gaussian integral is $\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}$, and a classic identity is $e^{i\\pi} + 1 = 0$ which appears mid-sentence here."),

            ("Block math",
             "A display equation:\n\n$$e^{i\\pi} + 1 = 0$$\n\nAnd a fraction:\n\n$$\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$"),

            ("Math stress: matrix, sum, cases",
             "$$\\sum_{i=0}^{n} i = \\frac{n(n+1)}{2}$$\n\n$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$\n\n$$f(x) = \\begin{cases} x & x \\geq 0 \\\\ -x & x < 0 \\end{cases}$$"),

            ("Citations in flowing text",
             "Rill renders Markdown that arrives token by token [1], re-lexing only the dirty tail [2] so finished blocks never re-render. See the notes [3] for the full story."),

            ("Footnote reference + definition",
             "Here is a statement with a footnote[^note] and another[^second].\n\n[^note]: This is the first footnote definition.\n[^second]: And the second one, slightly longer to test wrapping."),

            ("Long unbreakable token / URL",
             "A very long token supercalifragilisticexpialidocioussupercalifragilisticexpialidocious and a bare URL https://example.com/very/long/path/segment/that/keeps/going/and/going/forever/and/ever should not run off-screen."),

            ("Wide GFM table",
             "| Strategy | Per-delta cost | Dependencies | Math | Footnotes | Alerts |\n|---|---|---|---|---|---|\n| Full re-parse per snapshot | O(document) | varies | varies | varies | varies |\n| Rill incremental streaming | O(tail) | none | native | yes | yes |"),

            ("Code block with long lines",
             "```swift\nlet veryLongVariableName = someFunctionWithAReallyLongNameThatExceedsTheScreenWidth(argumentOne: 1, argumentTwo: 2, argumentThree: 3)\nprint(\"a single line of code that is definitely wider than any phone screen and should scroll or wrap gracefully\")\n```"),

            ("Nested lists, tight and loose",
             "- Top level one\n  - Nested A\n    - Deeply nested i\n    - Deeply nested ii\n  - Nested B\n- Top level two\n\n1. Ordered first\n2. Ordered second\n   1. Sub one\n   2. Sub two"),

            ("Task list",
             "- [x] Block lexer\n- [x] Incremental engine\n- [ ] Your next great idea\n- [ ] A task with a much longer label that should wrap onto a second line cleanly without clipping"),

            ("GitHub alerts",
             "> [!NOTE]\n> Useful information that users should know.\n\n> [!WARNING]\n> Critical content demanding attention.\n\n> [!TIP]\n> Helpful advice with a longer body that wraps across multiple lines to test the callout layout."),

            ("Headings 1-6",
             "# Heading 1\n## Heading 2\n### Heading 3\n#### Heading 4\n##### Heading 5\n###### Heading 6\n\nBody text after the headings to check spacing."),

            ("Emphasis combinations",
             "This has **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `inline code`, and a combination of **bold with `code` inside** plus *italic with [a link](https://example.com)*."),

            ("Links and autolinks",
             "A [labeled link](https://example.com \"with title\"), an autolink <https://example.com>, a bare URL https://example.com/path, and an [email](mailto:hi@example.com)."),

            ("Inline image fallback",
             "Before image ![a descriptive alt text](https://example.com/missing.png) after image, in a sentence that continues past the image to test wrapping."),

            ("Mixed inline kitchen sink",
             "Text with **bold**, a [link](https://example.com), a citation [1], `code`, inline math $x^2 + y^2 = z^2$, ~~strike~~, and *italic* all in one wrapping paragraph that spills onto several lines."),

            ("Blockquote nested",
             "> Level one quote.\n>\n> > Level two nested quote that is longer and should wrap within the quote indentation.\n>\n> Back to level one."),

            ("Long heading that wraps",
             "## A particularly long heading that is going to exceed the width of the screen and must wrap onto a second line without clipping or overflow"),

            ("List item with citation and wrapping",
             "- A list item with a long paragraph of text that wraps onto multiple lines and ends with a citation [1] to make sure inline references inside list items also flow correctly.\n- Rich ~~basic~~ streaming analytics [2]"),

            ("CJK and emoji wrapping",
             "Mixed scripts: 这是一段中文文本 mixed with English and emoji 🚀🎉🔥 to verify that wrapping and spacing handle non-Latin characters and emoji without clipping or collision."),

            ("Thematic break and hard breaks",
             "First line with a hard break  \nsecond line after the break.\n\n---\n\nContent after a thematic break."),

            ("Empty-ish and edge inline",
             "A sentence with an unbalanced **bold marker that never closes and a lone $ dollar sign and a trailing backslash \\\\ to test graceful degradation."),
        ]
        return raw.enumerated().map { QACase(id: $0.offset, title: $0.element.0, markdown: $0.element.1) }
    }()

    /// Returns the case for an index, clamped to the valid range.
    public static func `case`(at index: Int) -> QACase {
        let clamped = max(0, min(index, cases.count - 1))
        return cases[clamped]
    }
}

/// Renders a single ``QACase`` full-screen for screenshot-based visual QA.
public struct QACaseView: View {
    private let qaCase: QACase

    public init(_ qaCase: QACase) {
        self.qaCase = qaCase
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Case \(qaCase.id): \(qaCase.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
            ScrollView {
                MarkdownView(qaCase.markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }
}
